iSDK_Version = 0.1;

-- _G Globals
Obj_HQ = "obj_HQ";
Obj_GeneralParticleEmitter = "obj_GeneralParticleEmitter";

DAMAGE_TYPE_PHYSICAL 	= 0;
DAMAGE_TYPE_MAGICAL 	= 1;
DAMAGE_TYPE_TRUE 		= 2;

class "__BuffManager"
	function __BuffManager:__init()
		self.CachedBuffStacks = {};
		Callback.Add('Tick', function()
			self.CachedBuffStacks = {};
		end);
	end

	function __BuffManager:BuffIsValid(buff)
		return buff ~= nil and buff.startTime <= Game.Timer() and buff.expireTime >= Game.Timer();
	end

	function __BuffManager:CacheBuffs(unit)
		if self.CachedBuffStacks[unit.networkID] == nil then
			local t = {};
			for i = 1, unit.buffCount do
				local buff = unit:GetBuff(i);
				if self:BuffIsValid(buff) then
					t[buff.name] = buff.stacks;
				end
			end
			self.CachedBuffStacks[unit.networkID] = t;
		end
	end

	function __BuffManager:HasBuff(unit, name)
		self:CacheBuffs(unit);
		return self.CachedBuffStacks[unit.networkID][name] ~= nil;
	end

	function __BuffManager:GetBuffCount(unit, name)
		self:CacheBuffs(unit);
		local count = self.CachedBuffStacks[unit.networkID][name];
		return count ~= nil and count or -1;
	end

	function __BuffManager:GetBuff(unit, name)
		for i = 1, unit.buffCount do
			local buff = unit:GetBuff(i);
			if self:BuffIsValid(buff) then
				if buff.name == name then
					return buff;
				end
			end
		end
		return nil;
	end

class "__ItemManager"
	function __ItemManager:__init()
		self.ItemSlots = {};
		table.insert(self.ItemSlots, ITEM_1);
		table.insert(self.ItemSlots, ITEM_2);
		table.insert(self.ItemSlots, ITEM_3);
		table.insert(self.ItemSlots, ITEM_4);
		table.insert(self.ItemSlots, ITEM_5);
		table.insert(self.ItemSlots, ITEM_6);
		table.insert(self.ItemSlots, ITEM_7);
		self.CachedItems = {};
		Callback.Add('Tick', function()
			self.CachedItems = {};
		end);
	end

	function __ItemManager:CacheItems(unit)
		if self.CachedItems[unit.networkID] == nil then
			local t = {};
			for i, slot in ipairs(self.ItemSlots) do
				local item = unit:GetItemData(slot);
				if item ~= nil then
					t[item.itemID] = item;
				end
			end
			self.CachedItems[unit.networkID] = t;
		end
	end

	function __ItemManager:GetItemByID(unit, id)
		self:CacheItems(unit);
		return self.CachedItems[unit.networkID][id];
	end

	function __ItemManager:HasItem(unit, id)
		return self:GetItemByID(unit, id) ~= nil;
	end

class "__Damage"
	function __Damage:__init()

	end

	function __Damage:CalculateDamage(from, target, damageType, rawDamage, isAbility, isAutoAttackOrTargetted)
		if from == nil or target == nil then
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
			penetrationFlat = from.armorPen;
			penetrationPercent = from.armorPenPercent;
			bonusPenetrationPercent = from.bonusArmorPenPercent;

			--  Minions return wrong percent values.
			if from.type == Obj_AI_Minion then
				penetrationFlat = 0;
				penetrationPercent = 0;
				bonusPenetrationPercent = 0;
			elseif from.type == Obj_AI_Turret then
				penetrationFlat = 0;
				penetrationPercent = (not Utilities:IsBaseTurret(from)) and 0.25 or 0.75;
				bonusPenetrationPercent = 0;
			end
		elseif damageType == DAMAGE_TYPE_MAGICAL then
			baseResistance = math.max(target.magicResist - target.bonusMagicResist, 0);
			bonusResistance = target.bonusMagicResist;
			penetrationFlat = from.magicPen;
			penetrationPercent = from.magicPenPercent;
			bonusPenetrationPercent = 0;
		elseif damageType == DAMAGE_TYPE_TRUE then
			return rawDamage;
		end
		local resistance = baseResistance + bonusResistance;
		if resistance > 0 then
			if penetrationPercent > 0 then
				baseResistance = baseResistance * penetrationPercent;
				bonusResistance = bonusResistance * penetrationPercent;
			end
			if bonusPenetrationPercent > 0 then
				bonusResistance = bonusResistance * bonusPenetrationPercent;
			end
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
		local percentReceived = 1;
		local flatPassive = 0;

		local fromIsMinion = from.type == Obj_AI_Minion;
		local targetIsMinion = target.type == Obj_AI_Minion;

		local percentPassive = 1;
		if fromIsMinion and targetIsMinion then
			percentPassive = percentPassive * (1 + from.bonusDamagePercent);
		end

		local flatReceived = 0;
		if fromIsMinion and targetIsMinion then
			flatReceived = flatReceived - target.flatDamageReduction;
		end

		return math.max(percentReceived * percentPassive * percentMod * (rawDamage + flatPassive) + flatReceived, 0);
	end

	function __Damage:GetHeroAutoAttackDamage(from, target, staticDamage)
		local totalDamage = from.totalDamage;
		local targetIsMinion = target.type == Obj_AI_Minion;
		if targetIsMinion and Utilities:IsOtherMinion(target) then
			return 1;
		end
		return self:CalculateDamage(from, target, DAMAGE_TYPE_PHYSICAL, totalDamage, false, true);
	end

	function __Damage:GetAutoAttackDamage(from, target, respectPassives)
		if respectPassives == nil then
			respectPassives = true;
		end
		if from == nil or target == nil then
			return 0;
		end
		if respectPassives and from.type == Obj_AI_Hero then
			return self:GetHeroAutoAttackDamage(from, target, 0);
		end
		return self:CalculateDamage(from, target, DAMAGE_TYPE_PHYSICAL, from.totalDamage, false, true);
	end

class "__Utilities"
	function __Utilities:__init()
		self.SpecialAutoAttackRanges = {
			["Caitlyn"] = function(from, target)
				if target ~= nil and BuffManager:HasBuff(target, "CaitlynYordleTrapInternal") then
					return 650;
				end
				return 0;
			end,
		};
		self.SpecialMelees = {
			["Azir"] = function(target) return true end,
			["Thresh"] = function(target) return true end,
			["Velkoz"] = function(target) return true end,
			["Viktor"] = function(target) return BuffManager:HasBuff(target, "ViktorPowerTransferReturn") end,
		
			["HA_OrderMinionMelee"] = function(target) return true end,
			["HA_ChaosMinionMelee"] = function(target) return true end,
		
			["SRU_OrderMinionMelee"] = function(target) return true end,
			["SRU_ChaosMinionMelee"] = function(target) return true end,
		};
		self.BaseTurrets = {
			["SRUAP_Turret_Order3"] = true,
			["SRUAP_Turret_Order4"] = true,
			["SRUAP_Turret_Chaos3"] = true,
			["SRUAP_Turret_Chaos4"] = true,
		};
		self.Obj_AI_Bases = {
			[Obj_AI_Hero] = true,
			[Obj_AI_Minion] = true,
			[Obj_AI_Turret] = true,
		};
		self.Structures = {
			[Obj_AI_Barracks] = true,
			[Obj_AI_Turret] = true,
			[Obj_HQ] = true,
		};
		self.CachedValidTargets = {};
		Callback.Add('Tick', function()
			self.CachedValidTargets = {};
		end);
	end

	function __Utilities:GetAutoAttackRange(from, target)
		if from.type == Obj_AI_Minion then
			return 0;
		elseif from.type == Obj_AI_Turret then
			return 775;
		end
		local range = from.range + from.boundingRadius + (target ~= nil and (target.boundingRadius - 30) or 35);
		if self.SpecialAutoAttackRanges[from.charName] ~= nil then
			range = range + self.SpecialAutoAttackRanges[from.charName](from, target);
		end
		return range;
	end

	function __Utilities:IsMelee(target)
		if self.SpecialMelees[target.charName] ~= nil then
			return self.SpecialMelees[target.charName](target);
		end
		if target.type == Obj_AI_Hero then
			return target.range <= 300;
		else
			return false;
		end
	end

	function __Utilities:IsRanged(target)
		return not self:IsMelee(target);
	end

	function __Utilities:IsMonster(target)
		return target.team == 300;
	end

	function __Utilities:IsOtherMinion(target)
		return target.maxHealth <= 6;
	end

	function __Utilities:IsBaseTurret(turret)
		return self.BaseTurrets[turret.charName] ~= nil;
	end

	function __Utilities:IsObj_AI_Base(obj)
		return self.Obj_AI_Bases[obj.type] ~= nil;
	end

	function __Utilities:IsStructure(obj)
		return self.Structures[obj.type] ~= nil;
	end

	function __Utilities:IdEquals(a, b)
		if a == nil or b == nil then
			return false;
		end
		return a.networkID == b.networkID;
	end

	function __Utilities:GetDistanceSquared(a, b)
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

	function __Utilities:GetDistance(a, b)
		return math.sqrt(self:GetDistanceSquared(a, b));
	end

	function __Utilities:IsInRange(from, target, range)
		return self:GetDistanceSquared(from, target) <= range * range;
	end

	function __Utilities:IsInAutoAttackRange(from, target)
		return self:IsInRange(from, target, self:GetAutoAttackRange(from, target));
	end

	function __Utilities:TotalShield(target)
		local result = target.shieldAD + target.shieldAP;
		if target.charName == "Blitzcrank" then
			if not BuffManager:HasBuff(target, "BlitzcrankManaBarrierCD") and not BuffManager:HasBuff(target, "ManaBarrier") then
				result = result + target.mana / 2;
			end
		end
		return result;
	end

	function __Utilities:TotalShieldHealth(target)
		return target.health + self:TotalShield(target);
	end

	function __Utilities:TotalShieldMaxHealth(target)
		return target.maxHealth + self:TotalShield(target);
	end

	function __Utilities:GetLatency()
		return Game.Latency() / 1000;
	end

	function __Utilities:__IsValidTarget(target)
		if self:IsObj_AI_Base(target) and not target.valid then
			return false;
		end
		if target.dead or (not target.visible) or (not target.isTargetable) then
			return false;
		end
		return true;
	end

	function __Utilities:IsValidTarget(target)
		if target == nil or target.networkID == nil then
			return false;
		end
		if self.CachedValidTargets[target.networkID] == nil then
			self.CachedValidTargets[target.networkID] = self:__IsValidTarget(target);
		end
		return self.CachedValidTargets[target.networkID];
	end

class "__ObjectManager"
	function __ObjectManager:__init()
		self.Minions = nil;
		self.AllyMinions = nil;
		self.EnemyMinions = nil;
		self.OtherMinions = nil;
		self.Monsters = nil;
		self.Heroes = nil;
		self.AllyHeroes = nil;
		self.EnemyHeroes = nil;
		Callback.Add('Tick', function()
			self:OnTick();
		end);
	end

	function __ObjectManager:OnTick()
		self.Minions = nil;
		self.AllyMinions = nil;
		self.EnemyMinions = nil;
		self.OtherMinions = nil;
		self.Monsters = nil;
		self.Heroes = nil;
		self.AllyHeroes = nil;
		self.EnemyHeroes = nil;
	end

	function __ObjectManager:UpdateMinions()
		if self.Minions == nil or self.Monsters == nil or self.OtherMinions == nil then
			self.Minions = {};
			self.Monsters = {};
			self.OtherMinions = {};
			for i = 1, Game.MinionCount() do
				local minion = Game.Minion(i);
				if Utilities:IsValidTarget(minion) then
					if Utilities:IsOtherMinion(minion) then
						table.insert(self.OtherMinions, minion);
					elseif Utilities:IsMonster(minion) then
						table.insert(self.Monsters, minion);
					else
						table.insert(self.Minions, minion);
					end
				end
			end
		end
	end

	function __ObjectManager:GetMinions()
		self:UpdateMinions();
		return self.Minions;
	end

	function __ObjectManager:GetAllyMinions()
		self:UpdateMinions();
		if self.AllyMinions == nil then
			self.AllyMinions = {};
			for i, minion in ipairs(self.Minions) do
				if minion.isAlly then
					table.insert(self.AllyMinions, minion);
				end
			end
		end
		return self.AllyMinions;
	end

	function __ObjectManager:GetEnemyMinions()
		self:UpdateMinions();
		if self.EnemyMinions == nil then
			self.EnemyMinions = {};
			for i, minion in ipairs(self.Minions) do
				if minion.isEnemy then
					table.insert(self.EnemyMinions, minion);
				end
			end
		end
		return self.EnemyMinions;
	end

	function __ObjectManager:GetOtherMinions()
		self:UpdateMinions();
		return self.OtherMinions;
	end

	function __ObjectManager:GetMonsters()
		self:UpdateMinions();
		return self.Monsters;
	end

	function __ObjectManager:UpdateHeroes()
		if self.Heroes == nil then
			self.Heroes = {};
			for i = 1, Game.HeroCount() do
				local hero = Game.Hero(i);
				if Utilities:IsValidTarget(hero) then
					table.insert(self.Heroes, hero);
				end
			end
		end
	end

	function __ObjectManager:GetHeroes()
		self:UpdateHeroes();
		return self.Heroes;
	end

	function __ObjectManager:GetAllyHeroes()
		self:UpdateHeroes();
		if self.AllyHeroes == nil then
			self.AllyHeroes = {};
			for i, hero in ipairs(self.Heroes) do
				if hero.isAlly then
					table.insert(self.AllyHeroes, hero);
				end
			end
		end
		return self.AllyHeroes;
	end

	function __ObjectManager:GetEnemyHeroes()
		self:UpdateHeroes();
		if self.EnemyHeroes == nil then
			self.EnemyHeroes = {};
			for i, hero in ipairs(self.Heroes) do
				if hero.isEnemy then
					table.insert(self.EnemyHeroes, hero);
				end
			end
		end
		return self.EnemyHeroes;
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
			if Utilities:IsValidTarget(minion) then
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
			if Utilities:IsValidTarget(turret) then
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

	function __HealthPrediction:CheckNewState(target)
		local currentState = target.attackData.state;
		local prevState = self.AlliesState[target.networkID];
		if prevState ~= nil then
			if prevState ~= STATE_WINDUP and currentState == STATE_WINDUP then
				self:OnBasicAttack(target);
			end
		end
	end

	function __HealthPrediction:OnBasicAttack(sender)
		local targetHandle = sender.attackData.target;
		if targetHandle == nil or targetHandle <= 0 then
			return;
		end
		if Utilities:IsBaseTurret(sender) then -- fps drops
			return;
		end
		if not Utilities:IsInRange(myHero, sender, 1500) then
			return;
		end
		if self.IncomingAttacks[sender.networkID] == nil then
			self.IncomingAttacks[sender.networkID] = {};
		else
			for i, attack in ipairs(self.IncomingAttacks[sender.networkID]) do
				attack.IsActiveAttack = false;
			end
		end
		table.insert(self.IncomingAttacks[sender.networkID], __IncomingAttack(sender, targetHandle));
	end

	function __HealthPrediction:GetPrediction(target, time)
		local health = Utilities:TotalShieldHealth(target);
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
			value.Health = Utilities:TotalShieldHealth(value.Minion);
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
		self.SourceIsMelee = Utilities:IsMelee(self.Source);
		self.MissileSpeed = self.SourceIsMelee and math.huge or self.Source.attackData.projectileSpeed;
		self.SourcePosition = self.Source.pos;
		self.WindUpTime = self.Source.attackData.windUpTime;
		self.AnimationTime = self.Source.attackData.animationTime;
		self.StartTime = Game.Timer();
	end

	function __IncomingAttack:GetAutoAttackDamage(target)
		if self.AutoAttackDamage == nil then
			self.AutoAttackDamage = Damage:GetAutoAttackDamage(self.Source, target);
		end
		return self.AutoAttackDamage;
	end

	function __IncomingAttack:GetMissileTime(target)
		if self.SourceIsMelee then
			return 0;
		end
		return Utilities:GetDistance(self.SourcePosition, target) / self.MissileSpeed;
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
			delay = delay + Utilities:GetLatency() - 0.1;
			local timeTillHit = self.StartTime + self.WindUpTime + self:GetMissileTime(target) - Game.Timer();
			if timeTillHit <= -0.25 then
				self.Arrived = true;
			end
			if not self.Arrived then
				if self.IsActiveAttack and Utilities:IsValidTarget(self.Source) then
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
					if (not self.SourceIsMelee) or Utilities:IsValidTarget(self.Source) then
						damage = damage + self:GetAutoAttackDamage(target);
					end
				end
			end
		end
		return damage;
	end

GetWebResultAsync("https://raw.githubusercontent.com/jachicao/GoS/master/lib/iSDK.version",
	function(version)
		if tonumber(version) > tonumber(iSDK_Version) then
			print("New iSDK version found, please wait...");
			GetWebResultAsync("https://raw.githubusercontent.com/jachicao/GoS/master/lib/iSDK.changelog",
				function(changelog)
					print("Changelog: ");
					print(tostring(changelog));
					DownloadFileAsync("https://raw.githubusercontent.com/jachicao/GoS/master/lib/iSDK.lua", 
						COMMON_PATH.."iSDK.lua", 
						function()
							print("Done, please press 2x F6 to load!");
							return
						end);
				end)
		else
			if not _G.iSDK_Loaded then
				BuffManager = __BuffManager();
				ItemManager = __ItemManager();
				Damage = __Damage();
				Utilities = __Utilities();
				ObjectManager = __ObjectManager();
				_G.iSDK_Loaded = true;
			end
		end
	end);
