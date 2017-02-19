iSDK_Version = 0.1;

local LocalCallbackAdd				= Callback.Add;
local LocalCallbackDel				= Callback.Del;
local LocalDrawColor				= Draw.Color;
local LocalDrawCircle				= Draw.Circle;
local LocalDrawText					= Draw.Text;
local LocalControlMove				= Control.Move;
local LocalControlAttack			= Control.Attack;
local LocalControlKeyUp				= Control.KeyUp;
local LocalControlKeyDown			= Control.KeyDown;
local LocalGameLatency				= Game.Latency;
local LocalGameTimer				= Game.Timer;
local LocalGameHeroCount 			= Game.HeroCount;
local LocalGameHero 				= Game.Hero;
local LocalGameMinionCount 			= Game.MinionCount;
local LocalGameMinion 				= Game.Minion;
local LocalGameTurretCount 			= Game.TurretCount;
local LocalGameTurret 				= Game.Turret;
local LocalGameWardCount 			= Game.WardCount;
local LocalGameWard 				= Game.Ward;
local LocalGameObjectCount 			= Game.ObjectCount;
local LocalGameObject				= Game.Object;
local LocalGameIsChatOpen			= Game.IsChatOpen;
local LocalGameIsOnTop				= Game.IsOnTop;
local STATE_UNKNOWN					= STATE_UNKNOWN;
local STATE_ATTACK					= STATE_ATTACK;
local STATE_WINDUP					= STATE_WINDUP;
local STATE_WINDDOWN				= STATE_WINDDOWN;
local ITEM_1						= ITEM_1;
local ITEM_2						= ITEM_2;
local ITEM_3						= ITEM_3;
local ITEM_4						= ITEM_4;
local ITEM_5						= ITEM_5;
local ITEM_6						= ITEM_6;
local ITEM_7						= ITEM_7;
local _Q							= _Q;
local _W							= _W;
local _E							= _E;
local _R							= _R;
local HK_Q							= HK_Q;
local HK_W							= HK_W;
local HK_E							= HK_E;
local HK_R							= HK_R;
local HK_ITEM_1						= HK_ITEM_1;
local HK_ITEM_2						= HK_ITEM_2;
local HK_ITEM_3						= HK_ITEM_3;
local HK_ITEM_4						= HK_ITEM_4;
local HK_ITEM_5						= HK_ITEM_5;
local HK_ITEM_6						= HK_ITEM_6;
local HK_ITEM_7						= HK_ITEM_7;
local HK_SUMMONER_1					= HK_SUMMONER_1;
local HK_SUMMONER_2					= HK_SUMMONER_2;
local HK_TCO						= HK_TCO;
local HK_LUS						= HK_LUS;
local Obj_AI_SpawnPoint				= Obj_AI_SpawnPoint;
local Obj_AI_Camp					= Obj_AI_Camp;
local Obj_AI_Barracks				= Obj_AI_Barracks;
local Obj_AI_Hero					= Obj_AI_Hero;
local Obj_AI_Minion					= Obj_AI_Minion;
local Obj_AI_Turret					= Obj_AI_Turret;
local Obj_AI_LineMissle				= Obj_AI_LineMissle;
local Obj_AI_Shop					= Obj_AI_Shop;
local Obj_HQ 						= "obj_HQ";
local Obj_GeneralParticleEmitter	= "obj_GeneralParticleEmitter";

local LocalTableInsert				= table.insert;
local LocalTableSort				= table.sort;
local LocalTableRemove				= table.remove;
local tonumber						= tonumber;
local ipairs						= ipairs;
local pairs							= pairs;
local max 							= math.max;
local min 							= math.min;
local sqrt 							= math.sqrt;
local huge 							= math.huge;
local abs 							= math.abs;

local EPSILON						= 1E-12;

-- _G Globals
local COLOR_LIGHT_GREEN				= LocalDrawColor(255, 144, 238, 144);
local COLOR_ORANGE_RED				= LocalDrawColor(255, 255, 69, 0);
local COLOR_WHITE					= LocalDrawColor(255, 255, 255, 255);
local COLOR_BLACK					= LocalDrawColor(255, 0, 0, 0);
local COLOR_RED						= LocalDrawColor(255, 255, 0, 0);

local DAMAGE_TYPE_PHYSICAL	= 0;
local DAMAGE_TYPE_MAGICAL	= 1;
local DAMAGE_TYPE_TRUE		= 2;

local TARGET_SELECTOR_MODE_AUTO							= 1;
local TARGET_SELECTOR_MODE_MOST_STACK					= 2;
local TARGET_SELECTOR_MODE_MOST_ATTACK_DAMAGE			= 3;
local TARGET_SELECTOR_MODE_MOST_MAGIC_DAMAGE			= 4;
local TARGET_SELECTOR_MODE_LEAST_HEALTH					= 5;
local TARGET_SELECTOR_MODE_CLOSEST						= 6;
local TARGET_SELECTOR_MODE_HIGHEST_PRIORITY				= 7;
local TARGET_SELECTOR_MODE_LESS_ATTACK					= 8;
local TARGET_SELECTOR_MODE_LESS_CAST					= 9;
local TARGET_SELECTOR_MODE_NEAR_MOUSE					= 10;

local Linq = nil;
local Utilities = nil;
local BuffManager = nil;
local ItemManager = nil;
local Damage = nil;
local ObjectManager = nil;
local TargetSelector = nil;
local OW = nil;

local LoadCallbacks = {};
_G.AddLoadCallback = function(cb)
	LocalTableInsert(LoadCallbacks, cb);
end

LocalCallbackAdd('Load', function()
	local Loaded = false;
	local id = LocalCallbackAdd('Tick', function()
		if not Loaded then
			if LocalGameHeroCount() > 1 or LocalGameTimer() > 30 then
				for i = 1, #LoadCallbacks do
					LoadCallbacks[i]();
				end
				Loaded = true;
				LocalCallbackDel('Tick', id);
			end
		end
	end);
end);

class "__BuffManager"
	function __BuffManager:__init()
		self.CachedBuffStacks = {};
		LocalCallbackAdd('Tick', function()
			self.CachedBuffStacks = {};
		end);
	end

	function __BuffManager:BuffIsValid(buff)
		return buff ~= nil and buff.startTime <= LocalGameTimer() and buff.expireTime >= LocalGameTimer() and buff.count > 0;
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
		LocalCallbackAdd('Tick', function()
			self.CachedItems = {};
		end);
	end

	function __ItemManager:CacheItems(unit)
		if self.CachedItems[unit.networkID] == nil then
			local t = {};
			for i = 1, #self.ItemSlots do
				local slot = self.ItemSlots[i];
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
				args.RawTotal = args.RawTotal * t[self:GetMaxLevel(args.From)] * 0.01;
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
		self.TurretToMinionPercentMod = {};
		for i = 1, #ObjectManager.MinionTypesDictionary["Melee"] do
			local charName = ObjectManager.MinionTypesDictionary["Melee"][i];
			self.TurretToMinionPercentMod[charName] = 0.45;
		end
		for i = 1, #ObjectManager.MinionTypesDictionary["Ranged"] do
			local charName = ObjectManager.MinionTypesDictionary["Ranged"][i];
			self.TurretToMinionPercentMod[charName] = 0.7;
		end
		for i = 1, #ObjectManager.MinionTypesDictionary["Siege"] do
			local charName = ObjectManager.MinionTypesDictionary["Siege"][i];
			self.TurretToMinionPercentMod[charName] = 0.14;
		end
		for i = 1, #ObjectManager.MinionTypesDictionary["Super"] do
			local charName = ObjectManager.MinionTypesDictionary["Super"][i];
			self.TurretToMinionPercentMod[charName] = 0.05;
		end

	end

	function __Damage:GetMaxLevel(hero)
		return min(hero.levelData.lvl, 18);
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

		local fromIsMinion = from.type == Obj_AI_Minion;
		local targetIsMinion = target.type == Obj_AI_Minion;

		local baseResistance = 0;
		local bonusResistance = 0;
		local penetrationFlat = 0;
		local penetrationPercent = 0;
		local bonusPenetrationPercent = 0;

		if damageType == DAMAGE_TYPE_PHYSICAL then
			baseResistance = max(target.armor - target.bonusArmor, 0);
			bonusResistance = target.bonusArmor;
			penetrationFlat = from.armorPen;
			penetrationPercent = from.armorPenPercent;
			bonusPenetrationPercent = from.bonusArmorPenPercent;

			--  Minions return wrong percent values.
			if fromIsMinion then
				penetrationFlat = 0;
				penetrationPercent = 0;
				bonusPenetrationPercent = 0;
			elseif from.type == Obj_AI_Turret then
				penetrationPercent = (not Utilities:IsBaseTurret(from)) and 0.3 or 0.75;
				penetrationFlat = 0;
				bonusPenetrationPercent = 0;
			end
		elseif damageType == DAMAGE_TYPE_MAGICAL then
			baseResistance = max(target.magicResist - target.bonusMagicResist, 0);
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

		local percentPassive = 1;
		if fromIsMinion and targetIsMinion then
			percentPassive = percentPassive * (1 + from.bonusDamagePercent);
		end

		local flatReceived = 0;
		if fromIsMinion and targetIsMinion then
			flatReceived = flatReceived - target.flatDamageReduction;
		end

		return max(percentReceived * percentPassive * percentMod * (rawDamage + flatPassive) + flatReceived, 0);
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
		local targetIsMinion = target.type == Obj_AI_Minion;
		if respectPassives and from.type == Obj_AI_Hero then
			return self:GetHeroAutoAttackDamage(from, target, self:GetStaticAutoAttackDamage(from, targetIsMinion));
		end
		if targetIsMinion then
			if Utilities:IsOtherMinion(target) then
				return 1;
			end
			if from.type == Obj_AI_Turret and not Utilities:IsBaseTurret(from) then
				local percentMod = self.TurretToMinionPercentMod[target.charName];
				if percentMod ~= nil then
					return target.maxHealth * percentMod;
				end
			end
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
		};
		for i = 1, #ObjectManager.MinionTypesDictionary["Melee"] do
			local charName = ObjectManager.MinionTypesDictionary["Melee"][i];
			self.SpecialMelees[charName] = function(target) return true end;
		end
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

		LocalCallbackAdd('Tick', function()
			self.CachedValidTargets = {};
		end);
		--[[
		LocalCallbackAdd('WndMsg', function(msg, wParam)
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
		if abs(target.attackData.projectileSpeed) < EPSILON then
			return true;
		end
		if self.SpecialMelees[target.charName] ~= nil then
			return self.SpecialMelees[target.charName](target);
		end
		if target.type == Obj_AI_Hero then
			return target.range <= 275;
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
		return sqrt(self:GetDistanceSquared(a, b));
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
				result = result + target.mana * 0.5;
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
		return LocalGameLatency() * 0.001;
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

	function __Linq:Add(t, value)
		t[#t + 1] = value;
	end

class "__ObjectManager"
	function __ObjectManager:__init()
		local MinionMaps 		= { "SRU", "HA" };
		local MinionTeams 		= { "Chaos", "Order" };
		local MinionTypes 		= { "Melee", "Ranged", "Siege", "Super" };
		self.MinionNames = {};
		self.MinionTypesDictionary = {};
		for i = 1, #MinionMaps do
			local map = MinionMaps[i];
			for j = 1, #MinionTeams do
				local team = MinionTeams[j];
				for k = 1, #MinionTypes do
					local t = MinionTypes[k];
					if self.MinionTypesDictionary[t] == nil then
						self.MinionTypesDictionary[t] = {};
					end
					local charName = map .. "_" .. team .. "Minion" .. t;
					Linq:Add(self.MinionTypesDictionary[t], charName);
					Linq:Add(self.MinionNames, charName);
				end
			end
		end
	end

	function __ObjectManager:GetMinions()
		local result = {};
		for i = 1, LocalGameMinionCount() do
			local minion = LocalGameMinion(i);
			if Utilities:IsValidTarget(minion) then
				if Utilities:IsOtherMinion(minion) then

				elseif Utilities:IsMonster(minion) then

				else
					Linq:Add(result, minion);
				end
			end
		end
		return result;
	end

	function __ObjectManager:GetAllyMinions()
		local result = {};
		for i = 1, LocalGameMinionCount() do
			local minion = LocalGameMinion(i);
			if Utilities:IsValidTarget(minion) and minion.isAlly then
				if Utilities:IsOtherMinion(minion) then

				elseif Utilities:IsMonster(minion) then

				else
					Linq:Add(result, minion);
				end
			end
		end
		return result;
	end

	function __ObjectManager:GetEnemyMinions()
		local result = {};
		for i = 1, LocalGameMinionCount() do
			local minion = LocalGameMinion(i);
			if Utilities:IsValidTarget(minion) and minion.isEnemy then
				if Utilities:IsOtherMinion(minion) then

				elseif Utilities:IsMonster(minion) then

				else
					Linq:Add(result, minion);
				end
			end
		end
		return result;
	end

	function __ObjectManager:GetOtherMinions()
		local result = {};
		for i = 1, LocalGameWardCount() do
			local minion = LocalGameWard(i);
			if Utilities:IsValidTarget(minion) then
				if Utilities:IsOtherMinion(minion) then
					Linq:Add(result, minion);
				end
			end
		end
		return result;
	end

	function __ObjectManager:GetOtherAllyMinions()
		local result = {};
		for i = 1, LocalGameWardCount() do
			local minion = LocalGameWard(i);
			if Utilities:IsValidTarget(minion) and minion.isAlly then
				if Utilities:IsOtherMinion(minion) then
					Linq:Add(result, minion);
				end
			end
		end
		return result;
	end

	function __ObjectManager:GetOtherEnemyMinions()
		local result = {};
		for i = 1, LocalGameWardCount() do
			local minion = LocalGameWard(i);
			if Utilities:IsValidTarget(minion) and minion.isEnemy then
				if Utilities:IsOtherMinion(minion) then
					Linq:Add(result, minion);
				end
			end
		end
		return result;
	end

	function __ObjectManager:GetMonsters()
		local result = {};
		for i = 1, LocalGameMinionCount() do
			local minion = LocalGameMinion(i);
			if Utilities:IsValidTarget(minion) then
				if Utilities:IsOtherMinion(minion) then

				elseif Utilities:IsMonster(minion) then
					Linq:Add(result, minion);
				else
				end
			end
		end
		return result;
	end

	function __ObjectManager:GetHeroes()
		local result = {};
		for i = 1, LocalGameHeroCount() do
			local hero = LocalGameHero(i);
			if Utilities:IsValidTarget(hero) then
				Linq:Add(result, hero);
			end
		end
		return result;
	end

	function __ObjectManager:GetAllyHeroes()
		local result = {};
		for i = 1, LocalGameHeroCount() do
			local hero = LocalGameHero(i);
			if Utilities:IsValidTarget(hero) and hero.isAlly then
				Linq:Add(result, hero);
			end
		end
		return result;
	end

	function __ObjectManager:GetEnemyHeroes()
		local result = {};
		for i = 1, LocalGameHeroCount() do
			local hero = LocalGameHero(i);
			if Utilities:IsValidTarget(hero) and hero.isEnemy then
				Linq:Add(result, hero);
			end
		end
		return result;
	end

	function __ObjectManager:GetTurrets()
		local result = {};
		for i = 1, LocalGameTurretCount() do
			local turret = LocalGameTurret(i);
			if Utilities:IsValidTarget(turret) then
				Linq:Add(result, turret);
			end
		end
		return result;
	end

	function __ObjectManager:GetAllyTurrets()
		local result = {};
		for i = 1, LocalGameTurretCount() do
			local turret = LocalGameTurret(i);
			if Utilities:IsValidTarget(turret) and turret.isAlly then
				Linq:Add(result, turret);
			end
		end
		return result;
	end

	function __ObjectManager:GetEnemyTurrets()
		local result = {};
		for i = 1, LocalGameTurretCount() do
			local turret = LocalGameTurret(i);
			if Utilities:IsValidTarget(turret) and turret.isEnemy then
				Linq:Add(result, turret);
			end
		end
		return result;
	end

class "__HealthPrediction"
	function __HealthPrediction:__init()
		self.IncomingAttacks = {}; -- networkID => [__IncomingAttack]
		self.AlliesState = {}; -- networkID => state
		self.AlliesTarget = {}; -- handle => boolean
		LocalCallbackAdd('Tick', function()
			self:OnTick();
		end);
	end

	function __HealthPrediction:OnTick()
		local newAlliesState = {};
		local newAlliesTarget = {};
		local t = ObjectManager:GetAllyMinions();
		for i = 1, #t do
			local minion = t[i];
			self:CheckNewState(minion);
			newAlliesState[minion.networkID] = minion.attackData.state;
			local target = minion.attackData.target;
			if target ~= nil and target > 0 then
				newAlliesTarget[target] = true;
			end
		end
		local t = ObjectManager:GetAllyTurrets();
		for i = 1, #t do
			local turret = t[i];
			self:CheckNewState(turret);
			newAlliesState[turret.networkID] = turret.attackData.state;
		end
		local remove = {};
		-- remove older attacks
		for networkID, attacks in pairs(self.IncomingAttacks) do
			if #attacks > 0 then
				for i = 1, #attacks do
					if attacks[i]:ShouldRemove() then
						table.remove(attacks, i);
						break;
					end
				end
			else
				Linq:Add(remove, networkID);
			end
		end
		for i = 1, #remove do
			table.remove(self.IncomingAttacks, remove[i]);
		end
		self.AlliesState = newAlliesState;
		self.AlliesTarget = newAlliesTarget;
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

	function __HealthPrediction:IsTarget(target)
		return self.AlliesTarget[target.handle] ~= nil
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
			local t = self.IncomingAttacks[sender.networkID];
			for i = 1, #t do
				t[i].IsActiveAttack = false;
			end
		end
		Linq:Add(self.IncomingAttacks[sender.networkID], __IncomingAttack(sender, targetHandle));
	end

	function __HealthPrediction:GetPrediction(target, time)
		local health = Utilities:TotalShieldHealth(target);
		for _, attacks in pairs(self.IncomingAttacks) do
			if #attacks > 0 then
				for i = 1, #attacks do
					local attack = attacks[i];
					if attack:EqualsTarget(target) then
						health = health - attack:GetPredictedDamage(target, time);
					end
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
		self.MissileSpeed = self.SourceIsMelee and huge or self.Source.attackData.projectileSpeed;
		self.SourcePosition = self.Source.pos;
		self.WindUpTime = self.Source.attackData.windUpTime;
		self.AnimationTime = self.Source.attackData.animationTime;
		self.StartTime = self.Source.attackData.endTime - self.Source.attackData.animationTime;--LocalGameTimer();
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
		return self.Source == nil or self.Source.dead or LocalGameTimer() - self.StartTime > 3 or self.Arrived;
	end

	function __IncomingAttack:GetPredictedDamage(target, delay)
		local damage = 0;
		if not self:ShouldRemove() then
			delay = delay + Utilities:GetLatency() - 0.01;
			local timeTillHit = self.StartTime + self.WindUpTime + self:GetMissileTime(target) - LocalGameTimer();
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

	function __IncomingAttack:Draw(target)
		local damage = 0;
		if not self:ShouldRemove() then
			local timeTillHit = self.StartTime + self.WindUpTime + self:GetMissileTime(target) - LocalGameTimer();
			if timeTillHit <= 0 and timeTillHit > -0.25 then
				LocalDrawText("Will Hit: " .. timeTillHit, target.pos:To2D());
			end
		end
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
				LocalTableSort(targets, function(a, b)
					local first = self:GetReductedPriority(a) * Damage:CalculateDamage(myHero, a, (damageType == DAMAGE_TYPE_MAGICAL) and DAMAGE_TYPE_MAGICAL or DAMAGE_TYPE_PHYSICAL, 100) / a.health;
					local second = self:GetReductedPriority(b) * Damage:CalculateDamage(myHero, b, (damageType == DAMAGE_TYPE_MAGICAL) and DAMAGE_TYPE_MAGICAL or DAMAGE_TYPE_PHYSICAL, 100) / b.health;
					return first > second;
				end);
				return targets[1];
			end,
			[TARGET_SELECTOR_MODE_MOST_STACK] = function(targets, damageType)
				LocalTableSort(targets, function(a, b)
					local firstStack = 1;
					local secondStack = 1;
					local t = self.BuffStackNames["All"];
					for i = 1, #t do
						local buffName = t[i];
						firstStack = firstStack + max(0, BuffManager:GetBuffCount(a, buffName));
						secondStack = secondStack + max(0, BuffManager:GetBuffCount(b, buffName));
					end
					if self.BuffStackNames[myHero.charName] ~= nil then
						local t = self.BuffStackNames[myHero.charName];
						for i = 1, #t do
							local buffName = t[i];
							firstStack = firstStack + max(0, BuffManager:GetBuffCount(a, buffName)); 
							secondStack = secondStack + max(0, BuffManager:GetBuffCount(b, buffName));
						end
					end
					local first = firstStack * self:GetReductedPriority(a) * Damage:CalculateDamage(myHero, a, (damageType == DAMAGE_TYPE_MAGICAL) and DAMAGE_TYPE_MAGICAL or DAMAGE_TYPE_PHYSICAL, 100) / a.health;
					local second = secondStack * self:GetReductedPriority(b) * Damage:CalculateDamage(myHero, b, (damageType == DAMAGE_TYPE_MAGICAL) and DAMAGE_TYPE_MAGICAL or DAMAGE_TYPE_PHYSICAL, 100) / b.health;
					return first > second;
				end);
				return targets[1];
			end,
			[TARGET_SELECTOR_MODE_MOST_ATTACK_DAMAGE] = function(targets, damageType)
				LocalTableSort(targets, function(a, b)
					local first = a.totalDamage;
					local second = b.totalDamage;
					return first > second;
				end);
				return targets[1];
			end,
			[TARGET_SELECTOR_MODE_MOST_MAGIC_DAMAGE] = function(targets, damageType)
				LocalTableSort(targets, function(a, b)
					local first = a.ap;
					local second = b.ap;
					return first > second;
				end);
				return targets[1];
			end,
			[TARGET_SELECTOR_MODE_LEAST_HEALTH] = function(targets, damageType)
				LocalTableSort(targets, function(a, b)
					local first = a.health;
					local second = b.health;
					return first < second;
				end);
				return targets[1];
			end,
			[TARGET_SELECTOR_MODE_CLOSEST] = function(targets, damageType)
				LocalTableSort(targets, function(a, b)
					local first = Utilities:GetDistanceSquared(myHero, a);
					local second = Utilities:GetDistanceSquared(myHero, b);
					return first < second;
				end);
				return targets[1];
			end,
			[TARGET_SELECTOR_MODE_HIGHEST_PRIORITY] = function(targets, damageType)
				LocalTableSort(targets, function(a, b)
					local first = self:GetPriority(a);
					local second = self:GetPriority(b);
					return first > second;
				end);
				return targets[1];
			end,
			[TARGET_SELECTOR_MODE_LESS_ATTACK] = function(targets, damageType)
				LocalTableSort(targets, function(a, b)
					local first = self:GetReductedPriority(a) * Damage:CalculateDamage(myHero, a, DAMAGE_TYPE_PHYSICAL, 100) / a.health;
					local second = self:GetReductedPriority(b) * Damage:CalculateDamage(myHero, b, DAMAGE_TYPE_PHYSICAL, 100) / b.health;
					return first > second;
				end);
				return targets[1];
			end,
			[TARGET_SELECTOR_MODE_LESS_CAST] = function(targets, damageType)
				LocalTableSort(targets, function(a, b)
					local first = self:GetReductedPriority(a) * Damage:CalculateDamage(myHero, a, DAMAGE_TYPE_MAGICAL, 100) / a.health;
					local second = self:GetReductedPriority(b) * Damage:CalculateDamage(myHero, b, DAMAGE_TYPE_MAGICAL, 100) / b.health;
					return first > second;
				end);
				return targets[1];
			end,
			[TARGET_SELECTOR_MODE_NEAR_MOUSE] = function(targets, damageType)
				LocalTableSort(targets, function(a, b)
					local first = Utilities:GetDistanceSquared(a, mousePos);
					local second = Utilities:GetDistanceSquared(b, mousePos);
					return first < second;
				end);
				return targets[1];
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
		if LocalGameHeroCount() > 0 then
			for i = 1, LocalGameHeroCount() do
				local hero = LocalGameHero(i);
				if hero.isEnemy and not hero.isAlly then
					Linq:Add(EnemyHeroes, hero);
				end
			end
		end
		if #EnemyHeroes > 0 then
			for i = 1, #EnemyHeroes do
				local hero = EnemyHeroes[i];
				if self.EnemiesAdded[hero.charName] == nil then
					self.EnemiesAdded[hero.charName] = true;
					local priority = self.Priorities[hero.charName] ~= nil and self.Priorities[hero.charName] or 1;
					self.Menu.Priorities:MenuElement({ id = hero.charName, name = hero.charName, value = priority, min = 1, max = 5, step = 1 });
				end
			end
			self.Menu.Priorities:MenuElement({ id = "Reset", name = "Reset priorities to default values", value = true, callback = function()
				if self.Menu.Priorities.Reset:Value() then
					for charName, _ in pairs(self.EnemiesAdded) do
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
		
		LocalCallbackAdd('Draw', function()
			self:OnDraw();
		end);
		LocalCallbackAdd('WndMsg', function(msg, wParam)
			self:OnWndMsg(msg, wParam);
		end);
	end

	function __TargetSelector:OnDraw()
		if self.Menu.Drawings.SelectedTarget:Value() then
			if self.SelectedTarget ~= nil and Utilities:IsValidTarget(self.SelectedTarget) then
				LocalDrawCircle(self.SelectedTarget.pos, 120, 4, COLOR_RED);
			end
		end
	end

	function __TargetSelector:OnWndMsg(msg, wParam)
		if msg == WM_LBUTTONDOWN then
			if self.Menu.Advanced.SelectedTarget:Value() and not Utilities.MenuIsOpen then
				local t = ObjectManager:GetEnemyHeroes();
				for i = 1, #t do
					local hero = t[i];
					if Utilities:IsInRange(hero, mousePos, 100) then
						self.SelectedTarget = hero;
						break;
					end
				end
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
		local validTargets = {};
		for i = 1, #targets do
			local target = targets[i];
			if not Utilities:HasUndyingBuff(target) then
				Linq:Add(validTargets, target);
			end
		end
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
			for i = 1, #targets do
				if Utilities:IdEquals(targets[i], self.SelectedTarget) then
					return self.SelectedTarget;
				end
			end
		end
		local Mode = self.Menu.Mode:Value();
		if self.Selector[Mode] ~= nil then
			return self.Selector[Mode](targets, damageType);
		end
		return nil;
	end

if not _G.iSDK_Loaded then
	Linq = __Linq();
	ObjectManager = __ObjectManager();
	Utilities = __Utilities();
	BuffManager = __BuffManager();
	ItemManager = __ItemManager();
	Damage = __Damage();
	TargetSelector = __TargetSelector();
	_G.iSDK_Loaded = true;
end

local ORBWALKER_MODE_NONE				= -1;
local ORBWALKER_MODE_COMBO				= 0;
local ORBWALKER_MODE_HARASS				= 1;
local ORBWALKER_MODE_LANECLEAR			= 2;
local ORBWALKER_MODE_JUNGLECLEAR		= 3;
local ORBWALKER_MODE_LASTHIT			= 4;
local ORBWALKER_MODE_FLEE				= 5;

local ORBWALKER_TARGET_TYPE_HERO			= 0;
local ORBWALKER_TARGET_TYPE_MONSTER			= 1;
local ORBWALKER_TARGET_TYPE_MINION			= 2;
local ORBWALKER_TARGET_TYPE_STRUCTURE		= 3;

class "__Orbwalker"
	function __Orbwalker:__init()
		self.Menu = MenuElement({ id = "IC's Orbwalker", name = "IC's Orbwalker", type = MENU });

		self.DamageOnMinions = {};
		self.LastHitMinion = nil;
		self.AlmostLastHitMinion = nil;
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

		self.Modes = {
			[ORBWALKER_MODE_COMBO] = false,
			[ORBWALKER_MODE_HARASS] = false,
			[ORBWALKER_MODE_LANECLEAR] = false,
			[ORBWALKER_MODE_JUNGLECLEAR] = false,
			[ORBWALKER_MODE_LASTHIT] = false,
			[ORBWALKER_MODE_FLEE] = false,
		};

		self.OnUnkillableMinionCallbacks = {};
		self.OnPreAttackCallbacks = {};
		self.OnPreMovementCallbacks = {};

		self.LastHoldKey = 0;
		self.HoldKey = false;
		self.HoldPosition = nil;

		self.ExtraWindUpTimes = {
			["Jinx"] = 0.15,
			["Rengar"] = 0.15,
		};
		self.DisableAutoAttacks = {
			["Darius"] = function(unit)
				return BuffManager:HasBuff(unit, "DariusQCast");
			end,
			["Graves"] = function(unit)
				if abs(unit.hudAmmo) < EPSILON then
					return true;
				end
				return false;
			end,
			["Jhin"] = function(unit)
				if BuffManager:HasBuff(unit, "JhinPassiveReload") then
					return true;
				end
				if abs(unit.hudAmmo) < EPSILON then
					return true;
				end
				return false;
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
				local targets = {};
				local t = ObjectManager:GetEnemyHeroes();
				for i = 1, #t do
					local hero = t[i];
					if Utilities:IsInAutoAttackRange(myHero, hero) then
						Linq:Add(targets, hero);
					end
				end
				return TargetSelector:GetTarget(targets, DAMAGE_TYPE_PHYSICAL);
			end,
			[ORBWALKER_TARGET_TYPE_MONSTER] = function()
				local t = ObjectManager:GetMonsters();
				for i = 1, #t do
					local minion = t[i];
					if Utilities:IsInAutoAttackRange(myHero, minion) then
						return minion;
					end
				end
				return nil;
			end,
			[ORBWALKER_TARGET_TYPE_MINION] = function()
				local SupportMode = false;
				if self.Menu.General["SupportMode." .. myHero.charName]:Value() then
					local t = ObjectManager:GetAllyHeroes();
					for i = 1, #t do
						local hero = t[i];
						if (not hero.isMe) and Utilities:IsInRange(myHero, hero, 1500) then
							SupportMode = true;
							break;
						end
					end
				end
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
				for i = 1, #self.EnemyStructures do
					local structure = self.EnemyStructures[i];
					if Utilities:IsValidTarget(structure) and Utilities:IsInRange(myHero, structure, Utilities:GetAutoAttackRange(myHero, structure)) then
						return structure;
					end
				end
				return nil;
			end,
		};

		AddLoadCallback(function()
			self:OnLoad();
		end);
	end

	function __Orbwalker:OnLoad()
		self.HealthPrediction = __HealthPrediction();
		if LocalGameObjectCount() > 0 then
			for i = 1, LocalGameObjectCount() do
				local object = LocalGameObject(i);
				if object ~= nil and object.isEnemy and Utilities:IsStructure(object) then
					Linq:Add(self.EnemyStructures, object);
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
		
		LocalCallbackAdd('Tick', function()
			self:OnTick();
		end);
		LocalCallbackAdd('Draw', function()
			self:OnDraw();
		end);
	end

	function __Orbwalker:Clear()
		self.DamageOnMinions = {};
		self.LastHitMinion = nil;
		self.AlmostLastHitMinion = nil;
		self.LaneClearMinion = nil;
		self.CustomMissileSpeed = nil;
		self.CustomWindUpTime = nil;
		self.StaticAutoAttackDamage = nil;
	end

	function __Orbwalker:OnTick()
		self:Clear();
		self.Modes = self:GetModes();
		self.IsNone = self:HasMode(ORBWALKER_MODE_NONE);
		self.MyHeroCanMove = self:CanMove();
		self.MyHeroCanAttack = self:CanAttack();
		self.MyHeroIsMelee = Utilities:IsMelee(myHero);
		if (not self.IsNone) or self.Menu.Drawings.LastHittableMinions:Value() then
			self.OnlyLastHit = (not self.Modes[ORBWALKER_MODE_LANECLEAR]);
			if (not self.IsNone) or self.Menu.Drawings.LastHittableMinions:Value() then
				self:CalculateLastHittableMinions();
			end
		end
		if (not self.IsNone) then
			self:Orbwalk();
		end
	end

	function __Orbwalker:Orbwalk()
		if LocalGameIsChatOpen() or (not LocalGameIsOnTop()) then
			return;
		end
		if self.MyHeroCanAttack then
			local target = self:GetTarget();
			if target ~= nil then
				local args = {
					Target = target,
					Process = true,
				};
				for i = 1, #self.OnPreAttackCallbacks do
					self.OnPreAttackCallbacks[i](args);
				end
				if args.Process and args.Target ~= nil then
					self.LastAutoAttackSent = LocalGameTimer();
					LocalControlAttack(args.Target);
					self.HoldKey = false;
					self.HoldPosition = nil;
					return;
				end
			end
		end
		self:Move();
	end

	function __Orbwalker:GetLastIssueOrder()
		return max(self.LastAutoAttackSent, self.LastMovementSent);
	end

	function __Orbwalker:Move()
		if not self.MyHeroCanMove then
			return;
		end
		local MovementDelay = self.Menu.General.MovementDelay:Value() * 0.001;
		if LocalGameTimer() - self.LastMovementSent <= MovementDelay then
			return;
		end
		if (not self.Menu.General.FastKiting:Value()) and LocalGameTimer() - self.LastAutoAttackSent <= MovementDelay then
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
			for i = 1, #self.OnPreMovementCallbacks do
				self.OnPreMovementCallbacks[i](args);
			end
			if args.Process and args.Target ~= nil then
				self.LastMovementSent = LocalGameTimer();
				if args.Target == mousePos then
					LocalControlMove();
				else
					LocalControlMove(args.Target);
				end
				return;
			end
		end
		if hold then
			if self.HoldPosition == nil or (not (self.HoldPosition == myHero.pos)) then
				LocalControlKeyUp(72);
				self.HoldPosition = myHero.pos;
			end
			--[[
				if not self.HoldKey then
					LocalControlKeyDown(72);
					self.HoldKey = true;
					self.LastHoldKey = LocalGameTimer();
				else
					if self.LastHoldKey > 0 and LocalGameTimer() - self.LastHoldKey > 0.15 then
						self.LastHoldKey = 0;
					end
				end
			]]
		end
	end

	function __Orbwalker:OnDraw()
		if self.Menu.Drawings.Range:Value() then
			LocalDrawCircle(myHero.pos, Utilities:GetAutoAttackRange(myHero), COLOR_LIGHT_GREEN);
		end
		if self.Menu.Drawings.HoldRadius:Value() then
			LocalDrawCircle(myHero.pos, self.Menu.General.HoldRadius:Value(), COLOR_LIGHT_GREEN);
		end
		if self.Menu.Drawings.EnemyRange:Value() then
			local t = ObjectManager:GetEnemyHeroes();
			for i = 1, #t do
				local enemy = t[i];
				local range = Utilities:GetAutoAttackRange(enemy, myHero);
				LocalDrawCircle(enemy.pos, range, Utilities:IsInRange(enemy, myHero, range) and COLOR_ORANGE_RED or COLOR_LIGHT_GREEN);
			end
		end
		if self.Menu.Drawings.LastHittableMinions:Value() then
			if self.LastHitMinion ~= nil then
				LocalDrawCircle(self.LastHitMinion.pos, max(65, self.LastHitMinion.boundingRadius), COLOR_WHITE);
			end
			if self.AlmostLastHitMinion ~= nil and not Utilities:IdEquals(self.AlmostLastHitMinion, self.LastHitMinion) then
				LocalDrawCircle(self.AlmostLastHitMinion.pos, max(65, self.AlmostLastHitMinion.boundingRadius), COLOR_ORANGE_RED);
			end
		end
		--[[
		local EnemyMinionsInRange = ObjectManager:GetEnemyMinions();
		local Minions = {};
		for i = 1, #EnemyMinionsInRange do
			local minion = EnemyMinionsInRange[i];
			if Utilities:IsInRange(myHero, minion, 1500) then
				Minions[minion.handle] = minion;
			end
		end
		for _, attacks in pairs(self.HealthPrediction.IncomingAttacks) do
			if #attacks > 0 then
				for i = 1, #attacks do
					local attack = attacks[i];
					local minion = Minions[attack.TargetHandle];
					if minion ~= nil then
						attack:Draw(minion);
					end
				end
			end
		end
		]]
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
			if LocalGameTimer() - self.LastAutoAttackSent <= 0.15 + Utilities:GetLatency() then
				if state == STATE_ATTACK then
					return false;
				end
			end
		end
		if state == STATE_ATTACK then
			return true;
		end
		local ExtraWindUpTime = self.Menu.General.ExtraWindUpTime:Value() * 0.001;
		if self.ExtraWindUpTimes[unit.charName] ~= nil then
			ExtraWindUpTime = ExtraWindUpTime + self.ExtraWindUpTimes[unit.charName];
		end
		if LocalGameTimer() - (self:GetEndTime(unit) + ExtraWindUpTime - self:GetWindDownTime(unit)) >= 0 then
			return true;
		end
		return false;
	end

	function __Orbwalker:CanAttack(unit)
		unit = self:GetUnit(unit);
		if self.DisableAutoAttacks[unit.charName] ~= nil and self.DisableAutoAttacks[unit.charName](unit) then
			return false;
		end
		if unit.isMe then
			if LocalGameTimer() - self.LastAutoAttackSent <= 0.15 + Utilities:GetLatency() then
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
		return LocalGameTimer() - self:GetEndTime(unit) + Utilities:GetLatency() + 0.07 + Utilities:GetClickDelay() >= 0;
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
			return huge;
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
		local heroChecked = false;
		if self.Modes[ORBWALKER_MODE_COMBO] or self.Modes[ORBWALKER_MODE_HARASS] then
			hero = self:GetTargetByType(ORBWALKER_TARGET_TYPE_HERO);
			heroChecked = true;
		end

		local minion = nil;
		if self.Modes[ORBWALKER_MODE_HARASS] or self.Modes[ORBWALKER_MODE_LASTHIT] or self.Modes[ORBWALKER_MODE_LANECLEAR] then
			minion = self:GetTargetByType(ORBWALKER_TARGET_TYPE_MINION);
		end

		local monster = nil
		if self.Modes[ORBWALKER_MODE_JUNGLECLEAR] then
			monster = self:GetTargetByType(ORBWALKER_TARGET_TYPE_MONSTER);
		end

		local structure = nil;
		if self.Modes[ORBWALKER_MODE_HARASS] or self.Modes[ORBWALKER_MODE_LANECLEAR] then
			structure = self:GetTargetByType(ORBWALKER_TARGET_TYPE_STRUCTURE);
		end

		local LastHitPriority = self.Menu.Farming.LastHitPriority:Value();

		if self.Modes[ORBWALKER_MODE_COMBO] then
			Linq:Add(potentialTargets, hero);
		end

		if self.Modes[ORBWALKER_MODE_HARASS] then
			if structure ~= nil then
				if not LastHitPriority then
					Linq:Add(potentialTargets, structure);
				end
				Linq:Add(potentialTargets, minion);
				if LastHitPriority and not self:ShouldWait() then
					Linq:Add(potentialTargets, structure);
				end
			else
				if not heroChecked then
					hero = self:GetTargetByType(ORBWALKER_TARGET_TYPE_HERO);
					heroChecked = true;
				end
				if not LastHitPriority then
					Linq:Add(potentialTargets, hero);
				end
				Linq:Add(potentialTargets, minion);
				if LastHitPriority and not self:ShouldWait() then
					Linq:Add(potentialTargets, hero);
				end
			end
		end
		if self.Modes[ORBWALKER_MODE_LASTHIT] then
			Linq:Add(potentialTargets, minion);
		end
		if self.Modes[ORBWALKER_MODE_JUNGLECLEAR] then
			Linq:Add(potentialTargets, monster);
		end
		if self.Modes[ORBWALKER_MODE_LANECLEAR] then
			local LaneClearHeroes = self.Menu.General.LaneClearHeroes:Value();
			if structure ~= nil then
				if not LastHitPriority then
					Linq:Add(potentialTargets, structure);
				end
				if Utilities:IdEquals(minion, self.LastHitMinion) then
					Linq:Add(potentialTargets, minion);
				end
				if LastHitPriority and not self:ShouldWait() then
					Linq:Add(potentialTargets, structure);
				end
			else
				if not heroChecked then
					hero = self:GetTargetByType(ORBWALKER_TARGET_TYPE_HERO);
					heroChecked = true;
				end
				if not LastHitPriority and LaneClearHeroes then
					Linq:Add(potentialTargets, hero);
				end
				if Utilities:IdEquals(minion, self.LastHitMinion) then
					Linq:Add(potentialTargets, minion);
				end
				if LastHitPriority and LaneClearHeroes and not self:ShouldWait() then
					Linq:Add(potentialTargets, hero);
				end
				if Utilities:IdEquals(minion, self.LaneClearMinion) then
					Linq:Add(potentialTargets, minion);
				end
			end
		end
		for i = 1, #potentialTargets do
			local target = potentialTargets[i];
			if target ~= nil then
				return target;
			end
		end
		return nil;
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
		Linq:Add(self.MenuKeys[mode], key);
	end

	function __Orbwalker:HasMode(mode)
		if mode == ORBWALKER_MODE_NONE then
			for _, value in pairs(self:GetModes()) do
				if value then
					return false;
				end
			end
			return true;
		end
		for i = 1, #self.MenuKeys[mode] do
			local key = self.MenuKeys[mode][i];
			if key:Value() then
				return true;
			end
		end
		return false;
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
		local extraTime = 0;--TODO (not self:CanIssueOrder()) and max(0, self:GetEndTime() - LocalGameTimer()) or 0;
		local maxMissileTravelTime = self.MyHeroIsMelee and 0 or (Utilities:GetAutoAttackRange(myHero) / self:GetMissileSpeed());
		local Minions = {};
		local EnemyMinionsInRange = ObjectManager:GetEnemyMinions();
		local ExtraFarmDelay = self.Menu.Farming.ExtraFarmDelay:Value() * 0.001;
		for i = 1, #EnemyMinionsInRange do
			local minion = EnemyMinionsInRange[i];
			if Utilities:IsInRange(myHero, minion, 1500) then
				local windUpTime = self:GetWindUpTime(myHero, minion) + ExtraFarmDelay;
				local missileTravelTime = self.MyHeroIsMelee and 0 or (Utilities:GetDistance(myHero, minion) / self:GetMissileSpeed());
				local orbwalkerMinion = __OrbwalkerMinion(minion);
				orbwalkerMinion.LastHitTime = windUpTime + missileTravelTime + extraTime; -- + max(0, 2 * (Utilities:GetDistance(myHero, minion) - Utilities:GetAutoAttackRange(myHero, minion)) / myHero.ms);
				orbwalkerMinion.LaneClearTime = self:GetAnimationTime(myHero, minion) + windUpTime + maxMissileTravelTime;
				Minions[minion.handle] = orbwalkerMinion;
			end
		end
		for _, attacks in pairs(self.HealthPrediction.IncomingAttacks) do
			if #attacks > 0 then
				for i = 1, #attacks do
					local attack = attacks[i];
					local minion = Minions[attack.TargetHandle];
					if minion ~= nil then
						minion.LastHitHealth = minion.LastHitHealth - attack:GetPredictedDamage(minion.Minion, minion.LastHitTime);
						minion.LaneClearHealth = minion.LaneClearHealth - attack:GetPredictedDamage(minion.Minion, minion.LaneClearTime);
					end
				end
			end
		end
		local UnkillableMinions = {};
		local LastHitMinions = {};
		local AlmostLastHitMinions = {};
		local LaneClearMinions = {};
		for _, minion in pairs(Minions) do
			if minion:IsUnkillable() then
				Linq:Add(UnkillableMinions, minion);
			elseif minion:IsLastHittable() then
				Linq:Add(LastHitMinions, minion);
			elseif minion:IsAlmostLastHittable() then
				Linq:Add(AlmostLastHitMinions, minion);
			elseif minion:IsLaneClearable() then
				Linq:Add(LaneClearMinions, minion);
			end
		end
		LocalTableSort(UnkillableMinions, function(a, b)
			return a.LastHitHealth < b.LastHitHealth;
		end);

		LocalTableSort(LastHitMinions, function(a, b)
			if a.Minion.maxHealth == b.Minion.maxHealth then
				return a.LastHitHealth < b.LastHitHealth;
			else
				return a.Minion.maxHealth > b.Minion.maxHealth;
			end
		end);
		for i = 1, #LastHitMinions do
			local minion = LastHitMinions[i].Minion;
			if Utilities:IsInAutoAttackRange(myHero, minion) then
				self.LastHitMinion = minion;
				break;
			end
		end

		LocalTableSort(AlmostLastHitMinions, function(a, b)
			if a.Minion.maxHealth == b.Minion.maxHealth then
				return a.LaneClearHealth < b.LaneClearHealth;
			else
				return a.Minion.maxHealth > b.Minion.maxHealth;
			end
		end);
		for i = 1, #AlmostLastHitMinions do
			local minion = AlmostLastHitMinions[i].Minion;
			if Utilities:IsInAutoAttackRange(myHero, minion) then
				self.AlmostLastHitMinion = minion;
				break;
			end
		end

		local PushPriority = self.Menu.Farming.PushPriority:Value();
		LocalTableSort(LaneClearMinions, function(a, b)
			if PushPriority then
				return a.LaneClearHealth < b.LaneClearHealth;
			else
				return a.LaneClearHealth > b.LaneClearHealth;
			end
		end);

		for i = 1, #LaneClearMinions do
			local minion = LaneClearMinions[i].Minion;
			if Utilities:IsInAutoAttackRange(myHero, minion) then
				self.LaneClearMinion = minion;
				break;
			end
		end

		if self.AlmostLastHitMinion ~= nil then
			self.LastShouldWait = LocalGameTimer();
		end
	end

	function __Orbwalker:ShouldWait()
		return LocalGameTimer() - self.LastShouldWait <= 0.4 or self.AlmostLastHitMinion ~= nil;
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
		Linq:Add(self.OnUnkillableMinionCallbacks, cb);
	end

	function __Orbwalker:OnPreAttack(cb)
		Linq:Add(self.OnPreAttackCallbacks, cb);
	end

	function __Orbwalker:OnPreMovement(cb)
		Linq:Add(self.OnPreMovement, cb);
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
		if OW.HealthPrediction:IsTarget(self.Minion) then
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
		--[[
			if abs(self.LaneClearHealth - self.Minion.health) < 1E-12 then
				return true;
			end
		]]
		if not OW.HealthPrediction:IsTarget(self.Minion) then
			return true;
		end
		local percentMod = 2;
		if false --[[TODO]] then
			percentMod = percentMod * 2;
		end
		return self.LaneClearHealth > percentMod * OW:GetAutoAttackDamage(self.Minion);
	end

if not _G.ICOrbwalker then
	-- Disabling GoS orbwalker
	_G.Orbwalker.Enabled:Value(false);
	_G.Orbwalker.Drawings.Enabled:Value(false);

	OW = __Orbwalker();
	_G.ICOrbwalker = true;
end