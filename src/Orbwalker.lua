local CachedBuffNames = {}; -- networkID => buff.name => buff.stack
Callback.Add('Tick', function()
	CachedBuffNames = {};
end);
local function BuffIsValid(buff)
	return buff ~= nil and buff.startTime <= Game.Timer() and buff.expireTime >= Game.Timer();
end
local function HasBuff(source, name)
	if CachedBuffNames[source.networkID] == nil then
		local t = {};
		for i = 1, unit.buffCount do
			local buff = source:GetBuff(i)
			if BuffIsValid(buff) then
				t[buff.name] = buff.stack;
			end
		end
		CachedBuffNames[source.networkID] = t;
	end
	return CachedBuffNames[source.networkID][name] ~= nil;
end

local SpecialAutoAttackRanges = {
	["Caitlyn"] = function(source, target)
		if target ~= nil and HasBuff(target, "caitlynyordletrapinternal") then
			return 650;
		end
		return 0;
	end,
}
local function GetAutoAttackRange(source, target)
	if source.type == Obj_AI_Minion then
		return 0;
	elseif source.type == Obj_AI_Turret then
		return 775;
	end
	local range = source.range + source.boundingRadius + (target ~= nil and (boundingRadius - 30) or 35);
	if SpecialAutoAttackRanges[source.charName] ~= nil then
		range = range + SpecialAutoAttackRanges[source.charName](source, target);
	end
	return range;
end

local SpecialMelees = {
	["Azir"] = function(source) return true end,
	["Thresh"] = function(source) return true end,
	["Velkoz"] = function(source) return true end,
	["Viktor"] = function(source) return HasBuff(source, "viktorpowertransferreturn") end,

	["HA_OrderMinionMelee"] = function(source) return true end,
	["HA_ChaosMinionMelee"] = function(source) return true end,

	["SRU_OrderMinionMelee"] = function(source) return true end,
	["SRU_ChaosMinionMelee"] = function(source) return true end,
};
local function IsMelee(source)
	if SpecialMelees[source.charName] ~= nil then
		return SpecialMelees[source.charName](source);
	end
	if source.type == Obj_AI_Hero then
		return source.range <= 300;
	else
		return false;
	end
end

local function IsRanged(source)
	return not IsMelee(source);
end

local BaseTurrets = {
	["SRUAP_Turret_Order3"] = true,
	["SRUAP_Turret_Order4"] = true,
	["SRUAP_Turret_Chaos3"] = true,
	["SRUAP_Turret_Chaos4"] = true
};
local function IsBaseTurret(turret)
	return BaseTurrets[turret.charName] ~= nil;
end

local Obj_AI_Bases = {
	[Obj_AI_Hero] = true,
	[Obj_AI_Minion] = true,
	[Obj_AI_Turret] = true
};
local function IsObj_AI_Base(obj)
	return Obj_AI_Bases[obj.type] ~= nil;
end

local function IdEquals(source, target)
	if source == nil or target == nil then
		return false;
	end
	return source.networkID == target.networkID;
end

local CachedValidTargets = {};
Callback.Add('Tick', function()
	CachedValidTargets = {};
end);
local function __IsValidTarget(target)
	if IsObj_AI_Base(target) and not target.valid then
		return false;
	end
	if target.dead or (not target.visible) or (not target.isTargetable) then
		return false;
	end
	return true;
end
local function IsValidTarget(target)
	if target == nil or target.networkID == nil then
		return false;
	end
	if CachedValidTargets[target.networkID] == nil then
		CachedValidTargets[target.networkID] = __IsValidTarget(target);
	end
	return CachedValidTargets[target.networkID];
end

local function GetDistanceSquared(a, b)
	local aIsGameObject = a.pos ~= nil;
	local bIsGameObject = b.pos ~= nil;
	if aIsGameObject then
		a = a.pos;
	end
	if bIsGameObject then
		b = b.pos;
	end
	local x = (a.x - b.x);
	local y = (a.y - b.y);
	local z = (a.z - b.z);
	return x * x + y * y + z * z;
end

local function GetDistance(a, b)
	return math.sqrt(GetDistanceSquared(a, b));
end


local function IsInRange(source, target, range)
	return GetDistanceSquared(source, target) <= range * range;
end

local DAMAGE_TYPE_PHYSICAL 	= 0;
local DAMAGE_TYPE_MAGICAL 	= 1;
local DAMAGE_TYPE_TRUE 		= 2;
local function GetDamage(source, target, damageType, rawDamage, isAbility, isAutoAttackOrTargetted)
	if source == nil or target == nil then
		return 0;
	end
	if isAbility == nil then
		isAbility = true;
	end
	if isAutoAttackOrTargetted == nil then
		isAutoAttackOrTargetted = false;
	end
	local baseResistance = 0;
	local bonusResistance = 0;
	local penetrationFlat = 0;
	local penetrationPercent = 0;
	local bonusPenetrationPercent = 0;

	if damageType == DAMAGE_TYPE_PHYSICAL then
		baseResistance = math.max(target.armor - target.bonusArmor, 0);
		bonusResistance = target.bonusArmor;
		penetrationFlat = source.armorPen;
		penetrationPercent = source.armorPenPercent;
		bonusPenetrationPercent = source.bonusArmorPenPercent;

		--  Minions return wrong percent values.
		if source.type == Obj_AI_Minion then
			penetrationFlat = 0;
			penetrationPercent = 0;
			bonusPenetrationPercent = 0;
		elseif source.type == Obj_AI_Turret then
			penetrationFlat = 0;
			penetrationPercent = (not IsBaseTurret(source)) and 0.25 or 0.75;
			bonusPenetrationPercent = 0;
		end
	elseif damageType == DAMAGE_TYPE_MAGICAL then
		baseResistance = math.max(target.magicResist - target.bonusMagicResist, 0);
		bonusResistance = target.bonusMagicResist;
		penetrationFlat = source.magicPen;
		penetrationPercent = source.magicPenPercent;
		bonusPenetrationPercent = 0;
	elseif damageType == DAMAGE_TYPE_TRUE then
		return rawDamage;
	end
	local resistance = baseResistance + bonusResistance;
	if resistance > 0 then
		baseResistance = baseResistance * (1 - penetrationPercent);
		bonusResistance = bonusResistance * (1 - penetrationPercent);
		bonusResistance = bonusResistance * (1 - bonusPenetrationPercent);
		resistance = baseResistance + bonusResistance;
		resistance = resistance - penetrationFlat;
	end

	local percentMod = 1;
	-- Penetration cant reduce resistance below 0.
	if resistance >= 0 then
		percentMod = percentMod * (100 / (100 + resistance));
	else
		percentMod = percentMod * (2 - 100 / (100 - resistance));
	end
	local percentPassive = 1;
	local percentReceived = 1;
	local flatReceived = 0;
	local flatPassive = 0;

	return math.max(percentReceived * percentPassive * percentMod * (rawDamage + flatPassive) + flatReceived, 0);
end

local function GetHeroAutoAttackDamage(source, target, staticDamage)
	local totalDamage = source.totalDamage;
	return GetDamage(source, target, DAMAGE_TYPE_PHYSICAL, totalDamage, false, true);
end

local function GetAutoAttackDamage(source, target, respectPassives)
	if respectPassives == nil then
		respectPassives = true;
	end
	if source == nil or target == nil then
		return 0;
	end
	if respectPassives and source.type == Obj_AI_Hero then
		return GetHeroAutoAttackDamage(source, target, 0);
	end
	return GetDamage(source, target, DAMAGE_TYPE_PHYSICAL, source.totalDamage, false, true);
end

class "__HealthPrediction"
	function __HealthPrediction:__init()
		self.IncomingAttacks = {}; -- networkID => [__IncomingAttack]
		self.AlliesState = {}; -- networkID => state
		Callback.Add('Tick', function()
			self:OnTick();
		end);
	end

	function __HealthPrediction:OnTick()
		local newAlliesState = {};
		for i = 1, Game.MinionCount() do
			local minion = Game.Minion(i);
			if IsValidTarget(minion) then
				if minion.isAlly then
					self:CheckNewState(minion);
					newAlliesState[minion.networkID] = minion.attackData.state;
				end
			else
				if self.IncomingAttacks[minion.networkID] ~= nil then
					table.remove(self.IncomingAttacks, minion.networkID);
				end
			end
		end
		for i = 1, Game.TurretCount() do
			local turret = Game.Turret(i);
			if IsValidTarget(turret) then
				if turret.isAlly then
					self:CheckNewState(turret);
					newAlliesState[turret.networkID] = turret.attackData.state;
				end
			else
				if self.IncomingAttacks[turret.networkID] ~= nil then
					table.remove(self.IncomingAttacks, turret.networkID);
				end
			end
		end

		-- remove older attacks
		for i, attacks in pairs(self.IncomingAttacks) do
			for j, attack in ipairs(attacks) do
				if attack:ShouldRemove() then
					table.remove(attacks, j);
					break;
				end
			end
		end
		self.AlliesState = newAlliesState;
	end

	function __HealthPrediction:CheckNewState(source)
		local currentState = source.attackData.state;
		local prevState = self.AlliesState[source.networkID];
		if prevState ~= nil then
			if prevState ~= STATE_WINDUP and currentState == STATE_WINDUP then
				self:OnBasicAttack(source);
			end
		end
	end

	function __HealthPrediction:OnBasicAttack(source)
		local targetHandle = source.attackData.target;
		if targetHandle == nil or targetHandle <= 0 then
			return;
		end
		if IsBaseTurret(source) then -- fps drops
			return;
		end
		if not IsInRange(myHero, source, 1500) then
			return;
		end
		if self.IncomingAttacks[source.networkID] == nil then
			self.IncomingAttacks[source.networkID] = {};
		else
			for i, attack in ipairs(self.IncomingAttacks[source.networkID]) do
				attack.IsActiveAttack = false;
			end
		end
		table.insert(self.IncomingAttacks[source.networkID], __IncomingAttack(source, targetHandle));
	end

	function __HealthPrediction:GetPrediction(target, time)
		local health = target.health;
		for i, attacks in pairs(self.IncomingAttacks) do
			for j, attack in ipairs(attacks) do
				if attack:EqualsTarget(target) then
					health = health - attack:GetPredictedDamage(target, time);
				end
			end
		end
		return health;
	end

	function __HealthPrediction:GetPredictions(minions) -- [networkID => { Minion = GameObject, Time = time }]
		for networkID, value in pairs(minions) do
			value.Health = value.Minion.health;
		end

		for i, attacks in pairs(self.IncomingAttacks) do
			for j, attack in ipairs(attacks) do
				local minion = minions[attack.Target.networkID];
				if minion ~= nil then
					minion.Health = minion.Health - attack:GetPredictedDamage(minion.Minion, minion.Time);
				end
			end
		end

		return minions;
	end

class "__IncomingAttack"
	function __IncomingAttack:__init(source, targetHandle)
		self.Source = source;
		self.TargetHandle = targetHandle;
		self.SourceIsValid = true;
		self.Arrived = false;
		self.IsActiveAttack = true;
		self.SourceIsMelee = IsMelee(self.Source);
		self.MissileSpeed = self.SourceIsMelee and math.huge or self.Source.attackData.projectileSpeed;
		self.SourcePosition = self.Source.pos;
		self.WindUpTime = self.Source.attackData.windUpTime;
		self.AnimationTime = self.Source.attackData.animationTime;
		self.StartTime = Game.Timer();
	end

	function __IncomingAttack:GetAutoAttackDamage(target)
		if self.AutoAttackDamage == nil then
			self.AutoAttackDamage = GetAutoAttackDamage(self.Source, target);
		end
		return self.AutoAttackDamage;
	end

	function __IncomingAttack:GetMissileTime(target)
		if self.SourceIsMelee then
			return 0;
		end
		return GetDistance(self.SourcePosition, target) / self.MissileSpeed;
	end

	function __IncomingAttack:EqualsTarget(target)
		return target.handle == self.TargetHandle;
	end

	function __IncomingAttack:ShouldRemove()
		return Game.Timer() - self.StartTime > 3 or self.Arrived;
	end

	function __IncomingAttack:GetPredictedDamage(target, delay)
		local damage = 0;
		if not self:ShouldRemove() then
			delay = delay + Game.Latency() / 1000 - 0.1;
			local timeTillHit = self.StartTime + self.WindUpTime + self:GetMissileTime(target) - Game.Timer();
			if timeTillHit <= -0.25 then
				self.Arrived = true;
			end
			if not self.Arrived then
				if self.IsActiveAttack and IsValidTarget(self.Source) then
					local count = 0;
					while timeTillHit < delay do
						if timeTillHit > 0 then
							count = count + 1;
						end
						timeTillHit = timeTillHit + self.AnimationTime;
					end
					if count > 0 then
						damage = damage + self:GetAutoAttackDamage(target) * count;
					end
				elseif timeTillHit < delay and timeTillHit > 0 then
					if (not self.SourceIsMelee) or IsValidTarget(self.Source) then
						damage = damage + self:GetAutoAttackDamage(target);
					end
				end
			end
		end
		return damage;
	end

class "__Orbwalker"
	function __Orbwalker:__init()
		self.HealthPrediction = __HealthPrediction();
		Callback.Add('Draw', function()
			for i = 1, Game.MinionCount() do
				local minion = Game.Minion(i);
				if IsValidTarget(minion) then
					if minion.isEnemy then
						local predictedHealth = self.HealthPrediction:GetPrediction(minion, 0.6);
						if predictedHealth < minion.health then
							Draw.Text(tostring(minion.health - predictedHealth), minion.pos:To2D());
						end
					end
				end
			end
		end);
	end

_G.OW = __Orbwalker();