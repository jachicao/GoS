local specialMelees = {
	["Azir"] = true,
	["Thresh"] = true,
	["Velkoz"] = true
};

local function isMelee(source)
	if specialMelees[source.charName] ~= nil then
		return true;
	end
	return source.range < 250;
end

local function isRanged(source)
	return not isMelee(source);
end

local baseTurrets = {
	["SRUAP_Turret_Order3"] = true,
	["SRUAP_Turret_Order4"] = true,
	["SRUAP_Turret_Chaos3"] = true,
	["SRUAP_Turret_Chaos4"] = true
};
local function isBaseTurret(turret)
	return baseTurrets[turret.charName] ~= nil;
end

local Obj_AI_Bases = {
	[Obj_AI_Hero] = true,
	[Obj_AI_Minion] = true,
	[Obj_AI_Turret] = true
};
local function isObj_AI_Base(obj)
	return Obj_AI_Bases[obj.type] ~= nil;
end

local function isValidTarget(target)
	if target == nil then
		return false;
	end
	if isObj_AI_Base(target) and not target.valid then
		return false;
	end
	if target.dead or (not target.visible) or (not target.isTargetable) then
		return false;
	end
	return true;
end

local function getDistanceSquared(a, b)
	local x = (a.x - b.x);
	local y = (a.y - b.y);
	local z = (a.z - b.z);
	return x * x + y * y + z * z;
end

local function getDistance(a, b)
	return math.sqrt(getDistanceSquared(a, b));
end


local function isInRange(source, target, range)
	local sourceIsGameObject = source.pos ~= nil;
	local targetIsGameObject = target.pos ~= nil;
	local sourceVector = nil;
	local targetVector = nil;
	if sourceIsGameObject then
		sourceVector = source.pos;
	else
		sourceVector = source;
	end
	if targetIsGameObject then
		targetVector = target.pos;
	else
		targetVector = target;
	end
	return getDistanceSquared(sourceVector, targetVector) <= range * range;
end

class "__HealthPrediction"
	function __HealthPrediction:__init()
		self.IncomingAttacks = {}; -- networkID => [__IncomingAttack]
		self.AlliesState = {}; -- networkID => state
		self.EnemyMinionsHandle = {}; -- handle => networkID
		self.EnemyMinions = {}; -- networkID => GameObject
		Callback.Add('Tick', function()
			self:OnTick();
		end);
	end

	function __HealthPrediction:OnTick()
		self.EnemyMinionsHandle = {};
		self.EnemyMinions = {};
		local newAlliesState = {};
		for i = 1, Game.MinionCount() do
			local minion = Game.Minion(i);
			if isValidTarget(minion) then
				if minion.isAlly then
					self:CheckNewState(minion);
				elseif minion.isEnemy then
					self.EnemyMinionsHandle[minion.handle] = minion.networkID;
				end
			else
				if self.IncomingAttacks[minion.networkID] ~= nil then
					table.remove(self.IncomingAttacks, minion.networkID);
				end
			end
		end
		for i = 1, Game.TurretCount() do
			local turret = Game.Turret(i);
			if isValidTarget(turret) then
				if turret.isAlly then
					self:CheckNewState(turret);
				end
			else
				if self.IncomingAttacks[turret.networkID] ~= nil then
					table.remove(self.IncomingAttacks, turret.networkID);
				end
			end
		end
		self.AlliesState = newAlliesState;
	end

	function __HealthPrediction:CheckNewState(source)
		local currentState = source.attackData.state;
		local prevState = self.AlliesState[source.networkID];
		newAlliesState[source.networkID] = currentState;
		if prevState ~= nil then
			if prevState == STATE_ATTACK and currentState == STATE_WINDUP then
				self:OnBasicAttack(source);
			end
		end
	end

	function __HealthPrediction:OnBasicAttack(source)
		local target = self:GetAllyTarget(source);
		if target == nil then
			return;
		end
		if isBaseTurret(source) ~= nil then -- fps drops
			return;
		end
		if not isInRange(myHero, source, 1500) then
			return;
		end
		if self.IncomingAttacks[source.networkID] == nil then
			self.IncomingAttacks[source.networkID] = {};
		else
			for i, attack in ipairs(self.IncomingAttacks[source.networkID]) do
				attack.IsActiveAttack = false;
			end
		end
		table.insert(self.IncomingAttacks[source.networkID], __IncomingAttack(source, target, ));
	end

	function __HealthPrediction:GetAllyTarget(ally)
		local targetHandle = ally.attackData.target;
		if targetHandle ~= nil and targetHandle > 0 then
			return self:GetEnemyMinionByHandle(targetHandle);
		end
		return nil;
	end

	function __HealthPrediction:GetEnemyMinionByHandle(handle);
		local networkID = self.EnemyMinionsHandle[handle];
		if networkID ~= nil then
			return self:GetEnemyMinionByNetworkID(networkID);
		end
		return nil;
	end

	function __HealthPrediction:GetEnemyMinionByNetworkID(networkID)
		if self.EnemyMinions[networkID] == nil then
			self.EnemyMinions[networkID] = Game.GetObjectByNetID(networkID);
		end
		return self.EnemyMinions[networkID];
	end

class "__IncomingAttack"
	function __IncomingAttack:__init(source, target, projectileSpeed)
		self.IsActiveAttack = true;
	end