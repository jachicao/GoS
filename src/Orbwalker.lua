iSDK_Version = 0.1;

-- _G Globals
Obj_HQ = "obj_HQ";
Obj_GeneralParticleEmitter = "obj_GeneralParticleEmitter";

COLOR_LIGHT_GREEN		= Draw.Color(255, 144, 238, 144);
COLOR_ORANGE_RED		= Draw.Color(255, 255, 69, 0);
COLOR_WHITE				= Draw.Color(255, 255, 255, 255);
COLOR_BLACK				= Draw.Color(255, 0, 0, 0);
COLOR_RED				= Draw.Color(255, 255, 0, 0);

DAMAGE_TYPE_PHYSICAL	= 0;
DAMAGE_TYPE_MAGICAL		= 1;
DAMAGE_TYPE_TRUE		= 2;

TARGET_SELECTOR_MODE_AUTO						= 1;
TARGET_SELECTOR_MODE_MOST_STACK					= 2;
TARGET_SELECTOR_MODE_MOST_ATTACK_DAMAGE			= 3;
TARGET_SELECTOR_MODE_MOST_MAGIC_DAMAGE			= 4;
TARGET_SELECTOR_MODE_LEAST_HEALTH				= 5;
TARGET_SELECTOR_MODE_CLOSEST					= 6;
TARGET_SELECTOR_MODE_HIGHEST_PRIORITY			= 7;
TARGET_SELECTOR_MODE_LESS_ATTACK				= 8;
TARGET_SELECTOR_MODE_LESS_CAST					= 9;
TARGET_SELECTOR_MODE_NEAR_MOUSE					= 10;

local LoadCallbacks = {};
_G.AddLoadCallback = function(cb)
	table.insert(LoadCallbacks, cb);
end

Callback.Add('Load', function()
	local Loaded = false;
	local id = Callback.Add('Tick', function()
		if not Loaded then
			if Game.HeroCount() > 1 or Game.Timer() > 30 then
				for i, cb in ipairs(LoadCallbacks) do
					cb();
				end
				Loaded = true;
				Callback.Del('Tick', id);
			end
		end
	end);
end);

class "__BuffManager"
	function __BuffManager:__init()
		self.CachedBuffStacks = {};
		Callback.Add('Tick', function()
			self.CachedBuffStacks = {};
		end);
	end

	function __BuffManager:BuffIsValid(buff)
		return buff ~= nil and buff.startTime <= Game.Timer() and buff.expireTime >= Game.Timer() and buff.count > 0;
	end

	function __BuffManager:CacheBuffs(unit)
		if self.CachedBuffStacks[unit.networkID] == nil then
			local t = {};
			for i = 0, unit.buffCount do
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
		for i = 0, unit.buffCount do
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
		self.ItemSlots = {
			ITEM_1,
			ITEM_2,
			ITEM_3,
			ITEM_4,
			ITEM_5,
			ITEM_6,
			ITEM_7,
		};
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
				if item ~= nil and item.itemID > 0 then
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
		self.StaticPassives = {
			["Corki"] = function(args)
				args.RawTotal = args.RawTotal * 0.5;
				args.RawMagical = args.RawTotal;
			end,
			["Graves"] = function(args)
				local t = { 70, 71, 72, 74, 75, 76, 78, 80, 81, 83, 85, 87, 89, 91, 95, 96, 97, 100 };
				args.RawTotal = args.RawTotal * t[self:GetMaxLevel(args.From)] / 100;
			end,
			["Jinx"] = function(args)
				if BuffManager:HasBuff(args.From, "JinxQ") then
					args.RawTotal = args.RawTotal * 1.1;
				end
			end,
			["Kalista"] = function(args)
				args.RawTotal = args.RawTotal * 0.9;
			end,
		};
	end

	function __Damage:GetMaxLevel(hero)
		return math.min(hero.levelData.lvl, 18);
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

	function __Damage:GetStaticAutoAttackDamage(from, targetIsMinion)
		local args = {
			From = from,
			RawTotal = from.totalDamage,
			RawPhysical = 0,
			RawMagical = 0,
			CalculatedTrue = 0,
			CalculatedPhysical = 0,
			CalculatedMagical = 0,
			DamageType = DAMAGE_TYPE_PHYSICAL,
			TargetIsMinion = targetIsMinion,
		};
		if self.StaticPassives[from.charName] ~= nil then
			self.StaticPassives[from.charName](args);
		end
		return args;
	end

	function __Damage:GetHeroAutoAttackDamage(from, target, static)
		if targetIsMinion and Utilities:IsOtherMinion(target) then
			return 1;
		end
		local targetIsMinion = target.type == Obj_AI_Minion;
		local RawTotal = tonumber(static.RawTotal);
		local RawPhysical = tonumber(static.RawPhysical);
		local RawMagical = tonumber(static.RawMagical);
		local CalculatedTrue = tonumber(static.CalculatedTrue);
		local CalculatedPhysical = tonumber(static.CalculatedPhysical);
		local CalculatedMagical = tonumber(static.CalculatedMagical);
		local CriticalStrike = false;

		if static.DamageType == DAMAGE_TYPE_PHYSICAL then
			RawPhysical = RawPhysical + RawTotal;
		elseif static.DamageType == DAMAGE_TYPE_MAGICAL then
			RawMagical = RawMagical + RawTotal;
		elseif static.DamageType == DAMAGE_TYPE_TRUE then
			CalculatedTrue = CalculatedTrue + RawTotal;
		end

		if RawPhysical > 0 then
			CalculatedPhysical = CalculatedPhysical + self:CalculateDamage(from, target, DAMAGE_TYPE_PHYSICAL, RawPhysical, false, static.DamageType == DAMAGE_TYPE_PHYSICAL);
		end

		if RawMagical > 0 then
			CalculatedMagical = CalculatedMagical + self:CalculateDamage(from, target, DAMAGE_TYPE_MAGICAL, RawMagical, false, static.DamageType == DAMAGE_TYPE_MAGICAL);
		end

		local percentMod = 1;
		return percentMod * CalculatedPhysical + CalculatedMagical + CalculatedTrue;
	end

	function __Damage:GetAutoAttackDamage(from, target, respectPassives)
		if respectPassives == nil then
			respectPassives = true;
		end
		if from == nil or target == nil then
			return 0;
		end
		if respectPassives and from.type == Obj_AI_Hero then
			return self:GetHeroAutoAttackDamage(from, target, self:GetStaticAutoAttackDamage(from, target.type == Obj_AI_Minion));
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

		self.MenuIsOpen = false;

		Callback.Add('Tick', function()
			self.CachedValidTargets = {};
		end);
		--[[
		Callback.Add('WndMsg', function(msg, wParam)
			if wParam == 160 then
				if msg == KEY_DOWN then
					self.MenuIsOpen = not self.MenuIsOpen;
				end
			end
		end);
		]]
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

	function __Utilities:IsSiegeMinion(minion)
		return minion.charName:find("Siege");
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

	function __Utilities:GetDistanceSquared(a, b, addY)
		local aIsGameObject = a.pos ~= nil;
		local bIsGameObject = b.pos ~= nil;
		if aIsGameObject then
			a = a.pos;
		end
		if bIsGameObject then
			b = b.pos;
		end
		if addY then
			local x = (a.x - b.x);
			local y = (a.y - b.y);
			local z = (a.z - b.z);
			return x * x + y * y + z * z;
		else

			local x = (a.x - b.x);
			local z = (a.z - b.z);
			return x * x + z * z;
		end
	end

	function __Utilities:GetDistance(a, b, addY)
		return math.sqrt(self:GetDistanceSquared(a, b));
	end

	function __Utilities:IsInRange(from, target, range)
		return self:GetDistanceSquared(from, target) <= range * range;
	end

	function __Utilities:IsInAutoAttackRange(from, target)
		if from.charName == "Azir" then
			--TODO
		end
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


	function __Utilities:HasUndyingBuff(target)
		return false; --TODO
	end

	function __Utilities:GetClickDelay()
		return 0.03;
	end

class "__Linq"
	function __Linq:__init()

	end

	function __Linq:Where(t, func)
		local newTable = {};
		for i, value in ipairs(t) do
			if func(value) then
				table.insert(newTable, value);
			end
		end
		return newTable;
	end

	function __Linq:FirstOrDefault(t, func)
		if func ~= nil then
			for i, value in ipairs(t) do
				if func(value) then
					return value;
				end
			end
		else
			for i, value in ipairs(t) do
				return value;
			end
		end
		return nil;
	end

	function __Linq:Select(t, func)
		local newTable = {};
		for i, value in ipairs(t) do
			table.insert(newTable, func(value));
		end
		return newTable;
	end

	function __Linq:Any(t, func)
		for i, value in ipairs(t) do
			if func(value) then
				return true;
			end
		end
		return false;
	end

	function __Linq:Count(t, func)
		local count = 0;
		for i, value in ipairs(t) do
			if func(value) then
				count = count + 1;
			end
		end
		return count;
	end

	function __Linq:AddRange(a, b)
		for i, value in ipairs(b) do
			table.insert(a, value);
		end
		return a;
	end

	function __Linq:SortBy(t, func)
		if #t > 1 then
			table.sort(t, func);
		end
		return t;
	end

	function __Linq:Contains(t, obj)
		for i, value in ipairs(t) do
			if value == obj then
				return true;
			end
		end
		return false;
	end

class "__ObjectManager"
	function __ObjectManager:__init()
		self.Minions = nil;
		self.AllyMinions = nil;
		self.EnemyMinions = nil;
		self.OtherMinions = nil;
		self.OtherEnemyMinions = nil;
		self.OtherAllyMinions = nil;
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
			if Game.MinionCount() > 0 then
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
			if Game.WardCount() > 0 then
				for i = 1, Game.WardCount() do
					local minion = Game.Ward(i);
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
	end

	function __ObjectManager:GetMinions()
		self:UpdateMinions();
		return self.Minions;
	end

	function __ObjectManager:GetAllyMinions()
		self:UpdateMinions();
		if self.AllyMinions == nil then
			self.AllyMinions = Linq:Where(self.Minions, function(minion)
				return minion.isAlly;
			end);
		end
		return self.AllyMinions;
	end

	function __ObjectManager:GetEnemyMinions()
		self:UpdateMinions();
		if self.EnemyMinions == nil then
			self.EnemyMinions = Linq:Where(self.Minions, function(minion)
				return minion.isEnemy;
			end);
		end
		return self.EnemyMinions;
	end

	function __ObjectManager:GetOtherMinions()
		self:UpdateMinions();
		return self.OtherMinions;
	end

	function __ObjectManager:GetOtherEnemyMinions()
		self:UpdateMinions();
		if self.OtherEnemyMinions == nil then
			self.OtherEnemyMinions = Linq:Where(self.OtherMinions, function(minion)
				return minion.isEnemy;
			end);
		end
		return self.OtherEnemyMinions;
	end

	function __ObjectManager:GetOtherAllyMinions()
		self:UpdateMinions();
		if self.OtherAllyMinions == nil then
			self.OtherAllyMinions = Linq:Where(self.OtherMinions, function(minion)
				return minion.isAlly;
			end);
		end
		return self.OtherAllyMinions;
	end

	function __ObjectManager:GetMonsters()
		self:UpdateMinions();
		return self.Monsters;
	end

	function __ObjectManager:UpdateHeroes()
		if self.Heroes == nil then
			self.Heroes = {};
			if Game.HeroCount() > 0 then
				for i = 1, Game.HeroCount() do
					local hero = Game.Hero(i);
					if Utilities:IsValidTarget(hero) then
						table.insert(self.Heroes, hero);
					end
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
			self.AllyHeroes = Linq:Where(self.Heroes, function(hero)
				return hero.isAlly;
			end);
		end
		return self.AllyHeroes;
	end

	function __ObjectManager:GetEnemyHeroes()
		self:UpdateHeroes();
		if self.EnemyHeroes == nil then
			self.EnemyHeroes = Linq:Where(self.Heroes, function(hero)
				return hero.isEnemy;
			end);
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
		if Game.MinionCount() > 0 then
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
		end
		if Game.TurretCount() > 0 then
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
		self.StartTime = self.Source.attackData.endTime - self.Source.attackData.animationTime;--Game.Timer();
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
			delay = delay + Utilities:GetLatency() - 0.01 + Utilities:GetClickDelay();
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

class "__TargetSelector"
	function __TargetSelector:__init()
		self.Menu = MenuElement({ id = "TargetSelector", name = "IC's Target Selector", type = MENU });
		self.EnemiesAdded = {};
		self.SelectedTarget = nil;
		self.Modes = {
			"Auto",
			"Most Stack",
			"Most Attack Damage",
			"Most Magic Damage",
			"Least Health",
			"Closest",
			"Highest Priority",
			"Less Attack",
			"Less Cast",
			"Near Mouse",
		};
		self.Priorities = {
			["Aatrox"] = 2,
			["Ahri"] = 4,
			["Akali"] = 3,
			["Alistar"] = 1,
			["Amumu"] = 1,
			["Anivia"] = 4,
			["Annie"] = 4,
			["Ashe"] = 4,
			["AurelionSol"] = 4,
			["Azir"] = 4,
			["Bard"] = 1,
			["Blitzcrank"] = 1,
			["Brand"] = 4,
			["Braum"] = 1,
			["Caitlyn"] = 4,
			["Cassiopeia"] = 4,
			["Chogath"] = 2,
			["Corki"] = 4,
			["Darius"] = 2,
			["Diana"] = 3,
			["Draven"] = 4,
			["DrMundo"] = 1,
			["Ekko"] = 4,
			["Elise"] = 2,
			["Evelynn"] = 2,
			["Ezreal"] = 4,
			["FiddleSticks"] = 3,
			["Fiora"] = 3,
			["Fizz"] = 3,
			["Galio"] = 2,
			["Gangplank"] = 2,
			["Garen"] = 1,
			["Gnar"] = 1,
			["Gragas"] = 2,
			["Graves"] = 4,
			["Hecarim"] = 1,
			["Heimerdinger"] = 3,
			["Illaoi"] =  2,
			["Irelia"] = 2,
			["Ivern"] = 2,
			["Janna"] = 1,
			["JarvanIV"] = 1,
			["Jax"] = 2,
			["Jayce"] = 3,
			["Jhin"] = 4,
			["Jinx"] = 4,
			["Kalista"] = 4,
			["Karma"] = 4,
			["Karthus"] = 4,
			["Kassadin"] = 3,
			["Katarina"] = 4,
			["Kayle"] = 3,
			["Kennen"] = 4,
			["Khazix"] = 3,
			["Kindred"] = 4,
			["Kled"] = 2,
			["KogMaw"] = 4,
			["Leblanc"] = 4,
			["LeeSin"] = 2,
			["Leona"] = 1,
			["Lissandra"] = 3,
			["Lucian"] = 4,
			["Lulu"] = 1,
			["Lux"] = 4,
			["Malphite"] = 1,
			["Malzahar"] = 4,
			["Maokai"] = 2,
			["MasterYi"] = 4,
			["MissFortune"] = 4,
			["MonkeyKing"] = 1,
			["Mordekaiser"] = 3,
			["Morgana"] = 2,
			["Nami"] = 1,
			["Nasus"] = 1,
			["Nautilus"] = 1,
			["Nidalee"] = 3,
			["Nocturne"] = 2,
			["Nunu"] = 1,
			["Olaf"] = 1,
			["Orianna"] = 4,
			["Pantheon"] = 2,
			["Poppy"] = 2,
			["Quinn"] = 4,
			["Rammus"] = 1,
			["RekSai"] = 2,
			["Renekton"] = 1,
			["Rengar"] = 2,
			["Riven"] = 3,
			["Rumble"] = 2,
			["Ryze"] = 2,
			["Sejuani"] = 1,
			["Shaco"] = 3,
			["Shen"] = 1,
			["Shyvana"] = 1,
			["Singed"] = 1,
			["Sion"] = 1,
			["Sivir"] = 4,
			["Skarner"] = 1,
			["Sona"] = 1,
			["Soraka"] = 4,
			["Swain"] = 2,
			["Syndra"] = 4,
			["TahmKench"] = 1,
			["Taliyah"] = 3,
			["Talon"] = 4,
			["Taric"] = 1,
			["Teemo"] = 4,
			["Thresh"] = 1,
			["Tristana"] = 4,
			["Trundle"] = 2,
			["Tryndamere"] = 2,
			["TwistedFate"] = 4,
			["Twitch"] = 4,
			["Udyr"] = 2,
			["Urgot"] = 2,
			["Varus"] = 4,
			["Vayne"] = 4,
			["Veigar"] = 4,
			["Velkoz"] = 4,
			["Vi"] = 2,
			["Viktor"] = 4,
			["Vladimir"] = 3,
			["Volibear"] = 1,
			["Warwick"] = 1,
			["Xerath"] = 4,
			["XinZhao"] = 2,
			["Yasuo"] = 3,
			["Yorick"] = 1,
			["Zac"] = 1,
			["Zed"] = 4,
			["Ziggs"] = 4,
			["Zilean"] = 3,
			["Zyra"] = 1,
		};
		self.BuffStackNames = {
			["All"]			= { "BraumMark" },
			["Darius"]		= { "DariusHemo" },
			["Ekko"]		= { "EkkoStacks" },
			["Gnar"]		= { "GnarWProc" },
			["Kalista"]		= { "KalistaExpungeMarker" },
			["Kennen"]		= { "kennenmarkofstorm" },
			["Kindred"]		= { "KindredHitCharge", "kindredecharge" },
			["TahmKench"]	= { "tahmkenchpdebuffcounter" },
			["Tristana"]	= { "tristanaecharge" },
			["Twitch"]		= { "TwitchDeadlyVenom" },
			["Varus"]		= { "VarusWDebuff" },
			["Vayne"]		= { "VayneSilverDebuff" },
			["Velkoz"]		= { "VelkozResearchStack" },
			["Vi"]			= { "ViWProc" },	
		};
		self.Selector = {
			[TARGET_SELECTOR_MODE_AUTO] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local first = self:GetReductedPriority(a) * Damage:CalculateDamage(myHero, a, (damageType == DAMAGE_TYPE_MAGICAL) and DAMAGE_TYPE_MAGICAL or DAMAGE_TYPE_PHYSICAL, 100) / a.health;
					local second = self:GetReductedPriority(b) * Damage:CalculateDamage(myHero, b, (damageType == DAMAGE_TYPE_MAGICAL) and DAMAGE_TYPE_MAGICAL or DAMAGE_TYPE_PHYSICAL, 100) / b.health;
					return first > second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
			[TARGET_SELECTOR_MODE_MOST_STACK] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local firstStack = 1;
					local secondStack = 1;
					for i, buffName in ipairs(self.BuffStackNames["All"]) do
						firstStack = firstStack + math.max(0, BuffManager:GetBuffCount(a, buffName));
						secondStack = secondStack + math.max(0, BuffManager:GetBuffCount(b, buffName));
					end
					if self.BuffStackNames[myHero.charName] ~= nil then
						for i, buffName in ipairs(self.BuffStackNames[myHero.charName]) do
							firstStack = firstStack + math.max(0, BuffManager:GetBuffCount(a, buffName)); 
							secondStack = secondStack + math.max(0, BuffManager:GetBuffCount(b, buffName));
						end
					end
					local first = firstStack * self:GetReductedPriority(a) * Damage:CalculateDamage(myHero, a, (damageType == DAMAGE_TYPE_MAGICAL) and DAMAGE_TYPE_MAGICAL or DAMAGE_TYPE_PHYSICAL, 100) / a.health;
					local second = secondStack * self:GetReductedPriority(b) * Damage:CalculateDamage(myHero, b, (damageType == DAMAGE_TYPE_MAGICAL) and DAMAGE_TYPE_MAGICAL or DAMAGE_TYPE_PHYSICAL, 100) / b.health;
					return first > second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
			[TARGET_SELECTOR_MODE_MOST_ATTACK_DAMAGE] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local first = a.totalDamage;
					local second = b.totalDamage;
					return first > second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
			[TARGET_SELECTOR_MODE_MOST_MAGIC_DAMAGE] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local first = a.ap;
					local second = b.ap;
					return first > second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
			[TARGET_SELECTOR_MODE_LEAST_HEALTH] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local first = a.health;
					local second = b.health;
					return first < second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
			[TARGET_SELECTOR_MODE_CLOSEST] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local first = Utilities:GetDistanceSquared(myHero, a);
					local second = Utilities:GetDistanceSquared(myHero, b);
					return first < second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
			[TARGET_SELECTOR_MODE_HIGHEST_PRIORITY] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local first = self:GetPriority(a);
					local second = self:GetPriority(b);
					return first > second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
			[TARGET_SELECTOR_MODE_LESS_ATTACK] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local first = self:GetReductedPriority(a) * Damage:CalculateDamage(myHero, a, DAMAGE_TYPE_PHYSICAL, 100) / a.health;
					local second = self:GetReductedPriority(b) * Damage:CalculateDamage(myHero, b, DAMAGE_TYPE_PHYSICAL, 100) / b.health;
					return first > second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
			[TARGET_SELECTOR_MODE_LESS_CAST] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local first = self:GetReductedPriority(a) * Damage:CalculateDamage(myHero, a, DAMAGE_TYPE_MAGICAL, 100) / a.health;
					local second = self:GetReductedPriority(b) * Damage:CalculateDamage(myHero, b, DAMAGE_TYPE_MAGICAL, 100) / b.health;
					return first > second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
			[TARGET_SELECTOR_MODE_NEAR_MOUSE] = function(targets, damageType)
				local sort = Linq:SortBy(targets, function(a, b)
					local first = Utilities:GetDistanceSquared(a, mousePos);
					local second = Utilities:GetDistanceSquared(b, mousePos);
					return first < second;
				end);
				return Linq:FirstOrDefault(sort);
			end,
		};
		AddLoadCallback(function()
			self:OnLoad();
		end);
	end

	function __TargetSelector:OnLoad()
		self.Menu:MenuElement({ id = "Mode", name = "Mode", value = 1, drop = self.Modes });
		self.Menu:MenuElement({ id = "Priorities", name = "Priorities", type = MENU });
		local EnemyHeroes = {};
		if Game.HeroCount() > 0 then
			for i = 1, Game.HeroCount() do
				local hero = Game.Hero(i);
				if hero.isEnemy and not hero.isAlly then
					table.insert(EnemyHeroes, hero);
				end
			end
		end
		if #EnemyHeroes > 0 then
			for i, hero in ipairs(EnemyHeroes) do
				if self.EnemiesAdded[hero.charName] == nil then
					self.EnemiesAdded[hero.charName] = true;
					local priority = self.Priorities[hero.charName] ~= nil and self.Priorities[hero.charName] or 1;
					self.Menu.Priorities:MenuElement({ id = hero.charName, name = hero.charName, value = priority, min = 1, max = 5, step = 1 });
				end
			end
			self.Menu.Priorities:MenuElement({ id = "Reset", name = "Reset priorities to default values", value = true, callback = function()
				if self.Menu.Priorities.Reset:Value() then
					for charName, v in pairs(self.EnemiesAdded) do
						local priority = self.Priorities[charName] ~= nil and self.Priorities[charName] or 1;
						self.Menu.Priorities[charName]:Value(priority);
					end
					self.Menu.Priorities.Reset:Value(false);
				end
			end });
		end

		self.Menu:MenuElement({ id = "Advanced", name = "Advanced", type = MENU });
			self.Menu.Advanced:MenuElement({ id = "SelectedTarget", name = "Enable Select Target Manually", value = true });
			--TODO

		self.Menu:MenuElement({ id = "Drawings", name = "Drawings", type = MENU });
			self.Menu.Drawings:MenuElement({ id = "SelectedTarget", name = "Draw circle around Selected Target", value = true });
		
		Callback.Add('Draw', function()
			self:OnDraw();
		end);
		Callback.Add('WndMsg', function(msg, wParam)
			self:OnWndMsg(msg, wParam);
		end);
	end

	function __TargetSelector:OnDraw()
		if self.Menu.Drawings.SelectedTarget:Value() then
			if self.SelectedTarget ~= nil and Utilities:IsValidTarget(self.SelectedTarget) then
				Draw.Circle(self.SelectedTarget.pos, 120, 4, COLOR_RED);
			end
		end
	end

	function __TargetSelector:OnWndMsg(msg, wParam)
		if msg == WM_LBUTTONDOWN then
			if self.Menu.Advanced.SelectedTarget:Value() and not Utilities.MenuIsOpen then
				self.SelectedTarget = Linq:FirstOrDefault(ObjectManager:GetEnemyHeroes(), function(hero)
					return Utilities:IsInRange(hero, mousePos, 100);
				end);
			end
		end
		if msg == KEY_DOWN then
			--print(wParam);
		end
	end

	function __TargetSelector:GetPriority(target)
		if self.EnemiesAdded[target.charName] ~= nil then
			return self.Menu.Priorities[target.charName]:Value();
		end
		return self.Priorities[target.charName] ~= nil and self.Priorities[target.charName] or 1;
	end

	function __TargetSelector:GetReductedPriority(target)
		local priority = self:GetPriority(target);
		if priority == 5 then
			return 2.5;
		elseif priority == 4 then
			return 2;
		elseif priority == 3 then
			return 1.75;
		elseif priority == 2 then
			return 1.5;
		elseif priority == 1 then
			return 1;
		end
	end

	function __TargetSelector:GetTarget(targets, damageType)
		local validTargets = Linq:Where(targets, function(target)
			return not Utilities:HasUndyingBuff(target);
		end);
		if #validTargets > 0 then
			targets = validTargets;
		end
		local SelectedTargetIsValid = Utilities:IsValidTarget(self.SelectedTarget);
		
		if #targets == 0 then
			return nil;
		end
		if #targets == 1 then
			return targets[1];
		end
		if SelectedTargetIsValid then
			if Linq:Contains(targets, self.SelectedTarget) then
				return self.SelectedTarget;
			end
		end
		local Mode = self.Menu.Mode:Value();
		if self.Selector[Mode] ~= nil then
			return self.Selector[Mode](targets, damageType);
		end
		return nil;
	end

if not _G.iSDK_Loaded then
	BuffManager = __BuffManager();
	ItemManager = __ItemManager();
	Damage = __Damage();
	Utilities = __Utilities();
	ObjectManager = __ObjectManager();
	Linq = __Linq();
	TargetSelector = __TargetSelector();
	_G.iSDK_Loaded = true;
end

ORBWALKER_MODE_NONE				= -1;
ORBWALKER_MODE_COMBO			= 0;
ORBWALKER_MODE_HARASS			= 1;
ORBWALKER_MODE_LANECLEAR		= 2;
ORBWALKER_MODE_JUNGLECLEAR		= 3;
ORBWALKER_MODE_LASTHIT			= 4;
ORBWALKER_MODE_FLEE				= 5;

ORBWALKER_TARGET_TYPE_HERO			= 0;
ORBWALKER_TARGET_TYPE_MONSTER		= 1;
ORBWALKER_TARGET_TYPE_MINION		= 2;
ORBWALKER_TARGET_TYPE_STRUCTURE		= 3;

class "__Orbwalker"
	function __Orbwalker:__init()
		self.Menu = MenuElement({ id = "IC's Orbwalker", name = "IC's Orbwalker", type = MENU });

		self.DamageOnMinions = {};
		self.EnemyMinionsInRange = {};
		self.MonstersInRange = {};
		self.UnkillableMinions = {};
		self.LastHitMinions = {};
		self.LastHitMinion = nil;
		self.AlmostLastHitMinions = {};
		self.AlmostLastHitMinion = nil;
		self.LaneClearMinions = {};
		self.LaneClearMinion = nil;
		self.CustomMissileSpeed = nil;
		self.CustomWindUpTime = nil;
		self.StaticAutoAttackDamage = nil;

		self.EnemyStructures = {};

		self.LastAutoAttackSent = 0;
		self.LastMovementSent = 0;
		self.LastShouldWait = 0;
		self.ForceTarget = nil;
		self.ForceMovement = nil;

		self.IsNone = false;
		self.OnlyLastHit = false;

		self.MenuKeys = {
			[ORBWALKER_MODE_COMBO] = {},
			[ORBWALKER_MODE_HARASS] = {},
			[ORBWALKER_MODE_LANECLEAR] = {},
			[ORBWALKER_MODE_JUNGLECLEAR] = {},
			[ORBWALKER_MODE_LASTHIT] = {},
			[ORBWALKER_MODE_FLEE] = {},
		};

		self.OnUnkillableMinionCallbacks = {};
		self.OnPreAttackCallbacks = {};
		self.OnPreMovementCallbacks = {};

		self.LastHoldKey = 0;
		self.HoldKey = false;

		self.ExtraWindUpTimes = {
			["Jinx"] = 0.15,
			["Rengar"] = 0.15,
		};
		self.DisableAutoAttackBuffs = {
			["Darius"] = function(unit)
				return BuffManager:HasBuff(unit, "DariusQCast");
			end,
			["Graves"] = function(unit)
				return not BuffManager:HasBuff(unit, "GravesBasicAttackAmmo1");
			end,
			["Jhin"] = function(unit)
				return BuffManager:HasBuff(unit, "JhinPassiveReload");
			end,
		};
		self.SpecialWindUpTimes = {
		["TwistedFate"] = function(unit, target)
				if BuffManager:HasBuff(unit, "BlueCardPreAttack") or BuffManager:HasBuff(unit, "RedCardPreAttack") or BuffManager:HasBuff(unit, "GoldCardPreAttack") then
					return 0.13;
				end
				return nil;
			end,
		};

		self.SpecialMissileSpeeds = {
			["Jhin"] = function(unit, target)
				if BuffManager:HasBuff(unit, "jhinpassiveattackbuff") then
					return 3000;
				end
				return nil;
			end,
			["Jinx"] = function(unit, target)
				if BuffManager:HasBuff(unit, "JinxQ") then
					return 2000;
				end
				return nil;
			end,
			["Viktor"] = function(unit, target)
				if BuffManager:HasBuff(unit, "ViktorPowerTransferReturn") then
					return 3000;
				end
				return nil;
			end,
		};
		self.SupportHeroes = {
			["Alistar"]			= true,
			["Bard"]			= true,
			["Braum"]			= true,
			["Janna"]			= true,
			["Karma"]			= true,
			["Leona"]			= true,
			["Lulu"]			= true,
			["Morgana"]			= true,
			["Nami"]			= true,
			["Sona"]			= true,
			["Soraka"]			= true,
			["TahmKench"]		= true,
			["Taric"]			= true,
			["Thresh"]			= true,
			["Zilean"]			= true,
			["Zyra"]			= true,
		};

		self.TargetByType = {
			[ORBWALKER_TARGET_TYPE_HERO] = function()
				if myHero.charName == "Azir" then
					--TODO
				end
				return TargetSelector:GetTarget(Linq:Where(ObjectManager:GetEnemyHeroes(), function(hero)
					return Utilities:IsInAutoAttackRange(myHero, hero);
				end), DAMAGE_TYPE_PHYSICAL);
			end,
			[ORBWALKER_TARGET_TYPE_MONSTER] = function()
				return Linq:FirstOrDefault(self.MonstersInRange);
			end,
			[ORBWALKER_TARGET_TYPE_MINION] = function()
				local SupportMode = self.Menu.General["SupportMode." .. myHero.charName]:Value() and Linq:Any(ObjectManager:GetAllyHeroes(), function(hero)
					return (not hero.isMe) and Utilities:IsInRange(myHero, hero, 1500);
				end);
				local LastHit = (not SupportMode) or (BuffManager:GetBuffCount(myHero, "TalentReaper") > 0);
				if LastHit then
					if self.LastHitMinion ~= nil then
						if self.AlmostLastHitMinion ~= nil and not Utilities:IdEquals(self.AlmostLastHitMinion, self.LastHitMinion) and Utilities:IsSiegeMinion(self.AlmostLastHitMinion) then
							return nil;
						end
						return self.LastHitMinion;
					end
					if self:ShouldWait() or self.OnlyLastHit then
						return nil;
					end
					return (not SupportMode) and self.LaneClearMinion or nil;
				end
			end,
			[ORBWALKER_TARGET_TYPE_STRUCTURE] = function()
				return Linq:FirstOrDefault(self.EnemyStructures, function(structure)
					return Utilities:IsValidTarget(structure) and Utilities:IsInRange(myHero, structure, Utilities:GetAutoAttackRange(myHero, structure));
				end);
			end,
		};

		AddLoadCallback(function()
			self:OnLoad();
		end);
	end

	function __Orbwalker:OnLoad()
		self.HealthPrediction = __HealthPrediction();
		if Game.ObjectCount() > 0 then
			for i = 1, Game.ObjectCount() do
				local object = Game.Object(i);
				if object ~= nil and object.isEnemy and Utilities:IsStructure(object) then
					table.insert(self.EnemyStructures, object);
				end
			end
		end
			
		self.Menu:MenuElement({ id = "Keys", name = "Keys Settings", type = MENU });
			self.Menu.Keys:MenuElement({ id = "Combo", name = "Combo", key = string.byte(" ") });
			self:RegisterMenuKey(ORBWALKER_MODE_COMBO, self.Menu.Keys.Combo);
			self.Menu.Keys:MenuElement({ id = "Harass", name = "Harass", key = string.byte("C") });
			self:RegisterMenuKey(ORBWALKER_MODE_HARASS, self.Menu.Keys.Harass);
			self.Menu.Keys:MenuElement({ id = "LaneClear", name = "Lane Clear", key = string.byte("V") });
			self:RegisterMenuKey(ORBWALKER_MODE_LANECLEAR, self.Menu.Keys.LaneClear);
			self.Menu.Keys:MenuElement({ id = "JungleClear", name = "Jungle Clear", key = string.byte("V") });
			self:RegisterMenuKey(ORBWALKER_MODE_JUNGLECLEAR, self.Menu.Keys.JungleClear);
			self.Menu.Keys:MenuElement({ id = "LastHit", name = "Last Hit", key = string.byte("X") });
			self:RegisterMenuKey(ORBWALKER_MODE_LASTHIT, self.Menu.Keys.LastHit);
			self.Menu.Keys:MenuElement({ id = "Flee", name = "Flee", key = string.byte("T") });
			self:RegisterMenuKey(ORBWALKER_MODE_FLEE, self.Menu.Keys.Flee);

		self.Menu:MenuElement({ id = "General", name = "General Settings", type = MENU });
			self.Menu.General:MenuElement({ id = "FastKiting", name = "Fast Kiting", value = true });
			self.Menu.General:MenuElement({ id = "LaneClearHeroes", name = "Attack heroes in Lane Clear mode", value = true });
			self.Menu.General:MenuElement({ id = "StickToTarget", name = "Stick to target (only melee)", value = true });
			self.Menu.General:MenuElement({ id = "MovementDelay", name = "Movement Delay", value = 250, min = 0, max = 1000, step = 25 });
			self.Menu.General:MenuElement({ id = "SupportMode." .. myHero.charName, name = "Support Mode", value = self.SupportHeroes[myHero.charName] ~= nil });
			self.Menu.General:MenuElement({ id = "HoldRadius", name = "Hold Radius", value = 120, min = 100, max = 250, step = 10 });
			self.Menu.General:MenuElement({ id = "ExtraWindUpTime", name = "Extra WindUpTime", value = 40, min = 0, max = 200, step = 20 });

		self.Menu:MenuElement({ id = "Farming", name = "Farming Settings", type = MENU });
			self.Menu.Farming:MenuElement({ id = "LastHitPriority", name = "Priorize Last Hit over Harass", value = true });
			self.Menu.Farming:MenuElement({ id = "PushPriority", name = "Priorize Push over Freeze", value = true });
			self.Menu.Farming:MenuElement({ id = "ExtraFarmDelay", name = "ExtraFarmDelay", value = 0, min = -80, max = 80, step = 10 });
			self.Menu.Farming:MenuElement({ id = "Tiamat", name = "Use Tiamat/Hydra on unkillable minions", value = true });

		self.Menu:MenuElement({ id = "Drawings", name = "Drawings Settings", type = MENU });
			self.Menu.Drawings:MenuElement({ id = "Range", name = "AutoAttack Range", value = true });
			self.Menu.Drawings:MenuElement({ id = "EnemyRange", name = "Enemy AutoAttack Range", value = true });
			self.Menu.Drawings:MenuElement({ id = "HoldRadius", name = "Hold Radius", value = false });
			self.Menu.Drawings:MenuElement({ id = "LastHittableMinions", name = "Last Hittable Minions", value = true });
		
		Callback.Add('Tick', function()
			self:OnTick();
		end);
		Callback.Add('Draw', function()
			self:OnDraw();
		end);
	end

	function __Orbwalker:Clear()
		self.DamageOnMinions = {};
		self.EnemyMinionsInRange = {};
		self.MonstersInRange = {};
		self.UnkillableMinions = {};
		self.LastHitMinions = {};
		self.LastHitMinion = nil;
		self.AlmostLastHitMinions = {};
		self.AlmostLastHitMinion = nil;
		self.LaneClearMinions = {};
		self.LaneClearMinion = nil;
		self.CustomMissileSpeed = nil;
		self.CustomWindUpTime = nil;
		self.StaticAutoAttackDamage = nil;
	end

	function __Orbwalker:OnTick()
		self:Clear();
		self.IsNone = self:HasMode(ORBWALKER_MODE_NONE);
		self.MyHeroCanMove = self:CanMove();
		self.MyHeroCanAttack = self:CanAttack();
		self.MyHeroIsMelee = Utilities:IsMelee(myHero);
		if (not self.IsNone) or self.Menu.Drawings.LastHittableMinions:Value() then
			self.EnemyMinionsInRange = Linq:Where(ObjectManager:GetEnemyMinions(), function(minion)
				return Utilities:IsInRange(myHero, minion, 1500);
			end);
			self.OnlyLastHit = (not self:HasMode(ORBWALKER_MODE_LANECLEAR));
			if (not self.IsNone) or self.Menu.Drawings.LastHittableMinions:Value() then
				self:CalculateLastHittableMinions();
			end
		end
		if (not self.IsNone) then
			self.MonstersInRange = Linq:Where(ObjectManager:GetMonsters(), function(minion)
				return Utilities:IsInAutoAttackRange(myHero, minion);
			end);
			self:Orbwalk();
		end
	end

	function __Orbwalker:Orbwalk()
		if Game.IsChatOpen() or (not Game.IsOnTop()) then
			return;
		end
		if self.MyHeroCanAttack then
			local target = self:GetTarget();
			if target ~= nil then
				local args = {
					Target = target,
					Process = true,
				};
				for i, cb in ipairs(self.OnPreAttackCallbacks) do
					cb(args);
				end
				if args.Process and args.Target ~= nil then
					self.LastAutoAttackSent = Game.Timer();
					Control.Attack(args.Target);
					self.HoldKey = false;
					return;
				end
			end
		end
		self:Move();
	end

	function __Orbwalker:Move()
		if not self.MyHeroCanMove then
			return;
		end
		local MovementDelay = self.Menu.General.MovementDelay:Value() / 1000;
		if Game.Timer() - self.LastMovementSent <= MovementDelay then
			return;
		end
		if (not self.Menu.General.FastKiting:Value()) and Game.Timer() - self.LastAutoAttackSent <= MovementDelay then
			return;
		end
		local position = self:GetMovementPosition();
		local movePosition = Utilities:IsInRange(myHero, position, 100) and myHero.pos:Extend(position, 100) or position;
		local HoldRadius = self.Menu.General.HoldRadius:Value();
		local move = false;
		local hold = false;
		if HoldRadius > 0 then
			if Utilities:GetDistanceSquared(myHero, position) > HoldRadius * HoldRadius then
				move = true;
			else
				hold = true;
				--Hold
			end
		else
			move = true;
		end
		if move then
			local args = {
				Target = movePosition,
				Process = true,
			};
			for i, cb in ipairs(self.OnPreMovementCallbacks) do
				cb(args);
			end
			if args.Process and args.Target ~= nil then
				self.LastMovementSent = Game.Timer();
				Control.Move(movePosition);
				return;
			end
		end
		if hold then
			if not self.HoldKey then
				Control.KeyDown(72);
				self.HoldKey = true;
				self.LastHoldKey = Game.Timer();
			else
				if self.LastHoldKey > 0 and Game.Timer() - self.LastHoldKey > 0.15 then
					self.LastHoldKey = 0;
					Control.KeyUp(72);
				end
			end
		end
	end

	function __Orbwalker:OnDraw()
		if self.Menu.Drawings.Range:Value() then
			Draw.Circle(myHero.pos, Utilities:GetAutoAttackRange(myHero), COLOR_LIGHT_GREEN);
		end
		if self.Menu.Drawings.HoldRadius:Value() then
			Draw.Circle(myHero.pos, self.Menu.General.HoldRadius:Value(), COLOR_LIGHT_GREEN);
		end
		if self.Menu.Drawings.EnemyRange:Value() then
			for i, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
				local range = Utilities:GetAutoAttackRange(enemy, myHero);
				Draw.Circle(enemy.pos, range, Utilities:IsInRange(enemy, myHero, range) and COLOR_ORANGE_RED or COLOR_LIGHT_GREEN);
			end
		end
		if self.Menu.Drawings.LastHittableMinions:Value() then
			if self.LastHitMinion ~= nil then
				Draw.Circle(self.LastHitMinion.pos, math.max(65, self.LastHitMinion.boundingRadius), COLOR_WHITE);
			end
			if self.AlmostLastHitMinion ~= nil and not Utilities:IdEquals(self.AlmostLastHitMinion, self.LastHitMinion) then
				Draw.Circle(self.AlmostLastHitMinion.pos, math.max(65, self.AlmostLastHitMinion.boundingRadius), COLOR_ORANGE_RED);
			end
		end
	end

	function __Orbwalker:GetUnit(unit)
		return (unit ~= nil) and unit or myHero;
	end

	function __Orbwalker:CanMove(unit)
		unit = self:GetUnit(unit);
		local state = self:GetState(unit);
		if state == STATE_WINDDOWN then
			return true;
		end
		if unit.isMe then
			if Game.Timer() - self.LastAutoAttackSent <= 0.15 + Utilities:GetLatency() then
				if state == STATE_ATTACK then
					return false;
				end
			end
		end
		if state == STATE_ATTACK then
			return true;
		end
		local ExtraWindUpTime = self.Menu.General.ExtraWindUpTime:Value() / 1000;
		if self.ExtraWindUpTimes[unit.charName] ~= nil then
			ExtraWindUpTime = ExtraWindUpTime + self.ExtraWindUpTimes[unit.charName];
		end
		if Game.Timer() - (self:GetEndTime(unit) + ExtraWindUpTime - Utilities:GetLatency() - self:GetWindDownTime(unit)) >= 0 then
			return true;
		end
		return false;
	end

	function __Orbwalker:CanAttack(unit)
		unit = self:GetUnit(unit);
		if self.DisableAutoAttackBuffs[unit.charName] ~= nil and self.DisableAutoAttackBuffs[unit.charName](unit) then
			return false;
		end
		if unit.isMe then
			if Game.Timer() - self.LastAutoAttackSent <= 0.15 + Utilities:GetLatency() then
				local state = self:GetState(unit);
				if state == STATE_WINDUP or state == STATE_WINDDOWN then
					return false;
				end
			end
		end
		return self:CanIssueOrder(unit);
	end

	function __Orbwalker:CanIssueOrder(unit)
		unit = self:GetUnit(unit);
		if self:GetState(unit) == STATE_ATTACK then
			return true;
		end
		return Game.Timer() - self:GetEndTime(unit) + Utilities:GetLatency() + 0.07 + Utilities:GetClickDelay() >= 0;
	end

	function __Orbwalker:GetState(unit)
		unit = self:GetUnit(unit);
		return unit.attackData.state;
	end

	function __Orbwalker:GetWindDownTime(unit)
		unit = self:GetUnit(unit);
		return self:GetAnimationTime(unit) - self:GetWindUpTime(unit);
		--return unit.attackData.windDownTime;
	end

	function __Orbwalker:GetAnimationTime(unit, target)
		unit = self:GetUnit(unit);
		if unit.charName == "Azir" then
			--TODO
		end
		return unit.attackData.animationTime;
	end

	function __Orbwalker:GetEndTime(unit)
		unit = self:GetUnit(unit);
		return unit.attackData.endTime;
	end

	function __Orbwalker:GetWindUpTime(unit, target)
		unit = self:GetUnit(unit);
		if self.SpecialWindUpTimes[unit.charName] ~= nil then
			if unit.isMe then
				if self.CustomWindUpTime == nil then
					local windUpTime = self.SpecialWindUpTimes[unit.charName](unit);
					if windUpTime then
						self.CustomWindUpTime = windUpTime;
					else
						self.CustomWindUpTime = unit.attackData.windUpTime;
					end
				end
				return self.CustomWindUpTime;
			else
				local windUpTime = self.SpecialWindUpTimes[unit.charName](unit);
				if windUpTime then
					return windUpTime;
				end
			end
		end
		if unit.charName == "Azir" then
			--TODO
		end
		return unit.attackData.windUpTime;
	end

	function __Orbwalker:GetMissileSpeed(unit)
		unit = self:GetUnit(unit);
		if self.SpecialMissileSpeeds[unit.charName] ~= nil then
			if unit.isMe then
				if self.CustomMissileSpeed == nil then
					local projectileSpeed = self.SpecialMissileSpeeds[unit.charName](unit);
					if projectileSpeed then
						self.CustomMissileSpeed = projectileSpeed;
					else
						self.CustomMissileSpeed = unit.attackData.projectileSpeed;
					end
				end
				return self.CustomMissileSpeed;
			else
				local projectileSpeed = self.SpecialMissileSpeeds[unit.charName](unit);
				if projectileSpeed then
					return projectileSpeed;
				end
			end
		end
		if Utilities:IsMelee(unit) then
			return math.huge;
		end
		return unit.attackData.projectileSpeed;
	end

	function __Orbwalker:GetTarget()
		if Utilities:IsValidTarget(self.ForceTarget) then
			return Utilities:IsInAutoAttackRange(myHero, self.ForceTarget) and self.ForceTarget or nil;
		end
		if self.IsNone then
			return nil;
		end
		local potentialTargets = {};

		local hero = nil;
		if self:HasMode(ORBWALKER_MODE_COMBO) or self:HasMode(ORBWALKER_MODE_HARASS) then
			hero = self:GetTargetByType(ORBWALKER_TARGET_TYPE_HERO);
		end

		local minion = nil;
		if self:HasMode(ORBWALKER_MODE_HARASS) or self:HasMode(ORBWALKER_MODE_LASTHIT) or self:HasMode(ORBWALKER_MODE_LANECLEAR) then
			minion = self:GetTargetByType(ORBWALKER_TARGET_TYPE_MINION);
		end

		local monster = nil
		if self:HasMode(ORBWALKER_MODE_JUNGLECLEAR) then
			monster = self:GetTargetByType(ORBWALKER_TARGET_TYPE_MONSTER);
		end

		local structure = nil;
		if self:HasMode(ORBWALKER_MODE_HARASS) or self:HasMode(ORBWALKER_MODE_LANECLEAR) then
			structure = self:GetTargetByType(ORBWALKER_TARGET_TYPE_STRUCTURE);
		end

		local LastHitPriority = self.Menu.Farming.LastHitPriority:Value();

		if self:HasMode(ORBWALKER_MODE_COMBO) then
			table.insert(potentialTargets, hero);
		end

		if self:HasMode(ORBWALKER_MODE_HARASS) then
			if structure ~= nil then
				if not LastHitPriority then
					table.insert(potentialTargets, structure);
				end
				table.insert(potentialTargets, minion);
				if LastHitPriority and not self:ShouldWait() then
					table.insert(potentialTargets, structure);
				end
			else
				if hero == nil then
					hero = self:GetTargetByType(ORBWALKER_TARGET_TYPE_HERO);
				end
				if not LastHitPriority then
					table.insert(potentialTargets, hero);
				end
				table.insert(potentialTargets, minion);
				if LastHitPriority and not self:ShouldWait() then
					table.insert(potentialTargets, hero);
				end
			end
		end
		if self:HasMode(ORBWALKER_MODE_LASTHIT) then
			table.insert(potentialTargets, minion);
		end
		if self:HasMode(ORBWALKER_MODE_JUNGLECLEAR) then
			table.insert(potentialTargets, monster);
		end
		if self:HasMode(ORBWALKER_MODE_LANECLEAR) then
			local LaneClearHeroes = self.Menu.General.LaneClearHeroes:Value();
			if structure ~= nil then
				if not LastHitPriority then
					table.insert(potentialTargets, structure);
				end
				if Utilities:IdEquals(minion, self.LastHitMinion) then
					table.insert(potentialTargets, minion);
				end
				if LastHitPriority and not self:ShouldWait() then
					table.insert(potentialTargets, structure);
				end
			else
				if hero == nil then
					hero = self:GetTargetByType(ORBWALKER_TARGET_TYPE_HERO);
				end
				if not LastHitPriority and LaneClearHeroes then
					table.insert(potentialTargets, hero);
				end
				if Utilities:IdEquals(minion, self.LastHitMinion) then
					table.insert(potentialTargets, minion);
				end
				if LastHitPriority and LaneClearHeroes and not self:ShouldWait() then
					table.insert(potentialTargets, hero);
				end
				if Utilities:IdEquals(minion, self.LaneClearMinion) then
					table.insert(potentialTargets, minion);
				end
			end
		end
		return Linq:FirstOrDefault(potentialTargets, function(target)
			return target ~= nil;
		end);
	end

	function __Orbwalker:GetTargetByType(t)
		return (self.TargetByType[t] ~= nil) and self.TargetByType[t]() or nil;
	end

	function __Orbwalker:GetMovementPosition()
		if self.ForceMovement ~= nil then
			return self.ForceMovement;
		end
		return mousePos;
	end

	function __Orbwalker:RegisterMenuKey(mode, key)
		table.insert(self.MenuKeys[mode], key);
	end

	function __Orbwalker:HasMode(mode)
		if mode == ORBWALKER_MODE_NONE then
			for key, value in pairs(self:GetModes()) do
				if value then
					return false;
				end
			end
			return true;
		end
		return Linq:Any(self.MenuKeys[mode], function(key)
			return key:Value();
		end);
	end

	function __Orbwalker:GetModes()
		return {
			[ORBWALKER_MODE_COMBO] 			= self:HasMode(ORBWALKER_MODE_COMBO),
			[ORBWALKER_MODE_HARASS] 		= self:HasMode(ORBWALKER_MODE_HARASS),
			[ORBWALKER_MODE_LANECLEAR] 		= self:HasMode(ORBWALKER_MODE_LANECLEAR),
			[ORBWALKER_MODE_JUNGLECLEAR] 	= self:HasMode(ORBWALKER_MODE_JUNGLECLEAR),
			[ORBWALKER_MODE_LASTHIT] 		= self:HasMode(ORBWALKER_MODE_LASTHIT),
			[ORBWALKER_MODE_FLEE] 			= self:HasMode(ORBWALKER_MODE_FLEE),
		};
	end

	function __Orbwalker:CalculateLastHittableMinions()
		local extraTime = 0;--TODO (not self:CanIssueOrder()) and math.max(0, self:GetEndTime() - Game.Timer()) or 0;
		local maxMissileTravelTime = self.MyHeroIsMelee and 0 or (Utilities:GetAutoAttackRange(myHero) / self:GetMissileSpeed());
		local Minions = {};
		for i, minion in ipairs(self.EnemyMinionsInRange) do
			local windUpTime = self:GetWindUpTime(myHero, minion);
			local missileTravelTime = self.MyHeroIsMelee and 0 or (Utilities:GetDistance(myHero, minion) / self:GetMissileSpeed());
			local orbwalkerMinion = __OrbwalkerMinion(minion);
			orbwalkerMinion.LastHitTime = windUpTime + missileTravelTime + extraTime + math.max(0, 2 * (Utilities:GetDistance(myHero, minion) - Utilities:GetAutoAttackRange(myHero, minion)) / myHero.ms);
			orbwalkerMinion.LaneClearTime = self:GetAnimationTime(myHero, minion) + windUpTime + maxMissileTravelTime;
			Minions[minion.handle] = orbwalkerMinion;
		end
		for i, attacks in pairs(self.HealthPrediction.IncomingAttacks) do
			for j, attack in ipairs(attacks) do
				local minion = Minions[attack.TargetHandle];
				if minion ~= nil then
					minion.LastHitHealth = minion.LastHitHealth - attack:GetPredictedDamage(minion.Minion, minion.LastHitTime);
					minion.LaneClearHealth = minion.LaneClearHealth - attack:GetPredictedDamage(minion.Minion, minion.LaneClearTime);
				end
			end
		end
		local UnkillableMinions = {};
		local LastHitMinions = {};
		local AlmostLastHitMinions = {};
		local LaneClearMinions = {};
		for k, minion in pairs(Minions) do
			if minion:IsUnkillable() then
				table.insert(UnkillableMinions, minion);
			elseif minion:IsLastHittable() then
				table.insert(LastHitMinions, minion);
			elseif minion:IsAlmostLastHittable() then
				table.insert(AlmostLastHitMinions, minion);
			elseif minion:IsLaneClearable() then
				table.insert(LaneClearMinions, minion);
			end
		end
		Linq:SortBy(UnkillableMinions, function(a, b)
			return a.LastHitHealth < b.LastHitHealth;
		end);
		self.UnkillableMinions = Linq:Select(UnkillableMinions, function(m)
			return m.Minion;
		end);

		Linq:SortBy(LastHitMinions, function(a, b)
			if a.Minion.maxHealth == b.Minion.maxHealth then
				return a.LastHitHealth < b.LastHitHealth;
			else
				return a.Minion.maxHealth > b.Minion.maxHealth;
			end
		end);
		self.LastHitMinions = Linq:Select(LastHitMinions, function(m)
			return m.Minion;
		end);

		Linq:SortBy(AlmostLastHitMinions, function(a, b)
			if a.Minion.maxHealth == b.Minion.maxHealth then
				return a.LaneClearHealth < b.LaneClearHealth;
			else
				return a.Minion.maxHealth > b.Minion.maxHealth;
			end
		end);
		self.AlmostLastHitMinions = Linq:Select(AlmostLastHitMinions, function(m)
			return m.Minion;
		end);

		local PushPriority = self.Menu.Farming.PushPriority:Value();
		Linq:SortBy(LaneClearMinions, function(a, b)
			if PushPriority then
				return a.LaneClearHealth < b.LaneClearHealth;
			else
				return a.LaneClearHealth > b.LaneClearHealth;
			end
		end);
		self.LaneClearMinions = Linq:Select(LaneClearMinions, function(m)
			return m.Minion;
		end);

		self.LastHitMinion = Linq:FirstOrDefault(self.LastHitMinions, function(minion)
			return Utilities:IsInAutoAttackRange(myHero, minion);
		end);
		self.AlmostLastHitMinion = Linq:FirstOrDefault(self.AlmostLastHitMinions, function(minion)
			return Utilities:IsInAutoAttackRange(myHero, minion);
		end);
		self.LaneClearMinion = Linq:FirstOrDefault(self.LaneClearMinions, function(minion)
			return Utilities:IsInAutoAttackRange(myHero, minion);
		end);

		if self.AlmostLastHitMinion ~= nil then
			self.LastShouldWait = Game.Timer();
		end
	end

	function __Orbwalker:ShouldWait()
		return Game.Timer() - self.LastShouldWait <= 0.4 or self.AlmostLastHitMinion ~= nil;
	end

	function __Orbwalker:GetAutoAttackDamage(minion)
		if self.StaticAutoAttackDamage == nil then
			self.StaticAutoAttackDamage = Damage:GetStaticAutoAttackDamage(myHero, true);
		end
		if self.DamageOnMinions[minion.networkID] == nil then
			self.DamageOnMinions[minion.networkID] = Damage:GetHeroAutoAttackDamage(myHero, minion, self.StaticAutoAttackDamage);
		end
		return self.DamageOnMinions[minion.networkID];
	end

	function __Orbwalker:OnUnkillableMinion(cb)
		table.insert(self.OnUnkillableMinionCallbacks, cb);
	end

	function __Orbwalker:OnPreAttack(cb)
		table.insert(self.OnPreAttackCallbacks, cb);
	end

	function __Orbwalker:OnPreMovement(cb)
		table.insert(self.OnPreMovement, cb);
	end

class "__OrbwalkerMinion"
	function __OrbwalkerMinion:__init(minion)
		self.Minion = minion;
		self.LastHitHealth = self.Minion.health;
		self.LaneClearHealth = self.Minion.health;
		self.LastHitTime = 0;
		self.LaneClearTime = 0;
	end

	function __OrbwalkerMinion:IsUnkillable()
		return self.LastHitHealth < 0;
	end

	function __OrbwalkerMinion:IsLastHittable()
		return self.LastHitHealth <= OW:GetAutoAttackDamage(self.Minion);
	end

	function __OrbwalkerMinion:IsAlmostLastHittable()
		if self.LaneClearHealth < self.Minion.health then
			local health = (false) --[[TODO]] and self.LastHitHealth or self.LaneClearHealth;
			local percentMod = Utilities:IsSiegeMinion(self.Minion) and 1.5 or 1;
			return health <= percentMod * OW:GetAutoAttackDamage(self.Minion);
		end
		return false;
	end

	function __OrbwalkerMinion:IsLaneClearable()
		if OW.OnlyLastHit then
			return false;
		end
		local percentMod = 2;
		if false --[[TODO]] then
			percentMod = percentMod * 2;
		end
		return self.LaneClearHealth > percentMod * OW:GetAutoAttackDamage(self.Minion) or math.abs(self.LaneClearHealth - self.Minion.health) < 1E-12;
	end

if _G.OW == nil then
	-- Disabling GoS orbwalker
	_G.Orbwalker.Enabled:Value(false);
	_G.Orbwalker.Drawings.Enabled:Value(false);

	_G.OW = __Orbwalker();
end