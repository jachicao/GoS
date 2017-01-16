local PRINT_CONSOLE = false;

local menu = MenuElement({ id = "DeveloperTool", name = "DeveloperTool", type = MENU });
menu:MenuElement({ id = "attackData", name = "attackData", value = false });


local function isObj_AI_Base(obj)
	if obj.type ~= nil then
		return obj.type == Obj_AI_Hero or obj.type == Obj_AI_Minion or obj.type == Obj_AI_Turret;
	end
	return false;
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

local function isOnScreen(obj)
	return obj.pos:To2D().onScreen;
end

local function getValue(name, func)
	if PRINT_CONSOLE then
		print('Checking ' .. name);
	end
	return name .. ": " .. func() .. ", ";
end

local counters = {};
local function drawText(target, value)
	if counters[target.networkID] == nil then
		counters[target.networkID] = 0;
	else
		counters[target.networkID] = counters[target.networkID] + 1;
	end
	local position = target.pos:To2D();
	position.y = position.y + 30 + 18 * counters[target.networkID];
	Draw.Text(value, position);
end

local stateTable = {};
stateTable[STATE_UNKNOWN] 	= "STATE_UNKNOWN";
stateTable[STATE_ATTACK]	= "STATE_ATTACK";
stateTable[STATE_WINDUP] 	= "STATE_WINDUP";
stateTable[STATE_WINDDOWN] 	= "STATE_WINDDOWN";
local function convertState(state)
	return stateTable[state];
end

Callback.Add('Load', 
	function()
		local Obj_AI_Bases = {};
		local handles = {};
		Callback.Add('Tick', function()
			Obj_AI_Bases = {};
			handles = {};
			for i = 1, Game.ObjectCount() do
				local obj = Game.Object(i);
				if isValidTarget(obj) and isObj_AI_Base(obj) and isOnScreen(obj) then
					table.insert(Obj_AI_Bases, obj);
					handles[obj.handle] = obj;
				end
			end
		end);

		Callback.Add('Draw', function()
			counters = {};
			for i, obj in ipairs(Obj_AI_Bases) do
				if menu.attackData:Value() then
					drawText(obj, getValue('state', function()
						return convertState(obj.attackData.state);
					end));
					drawText(obj, getValue('windUpTime', function()
						return obj.attackData.windUpTime;
					end));
					drawText(obj, getValue('windDownTime', function()
						return obj.attackData.windDownTime;
					end));
					drawText(obj, getValue('animationTime', function()
						return obj.attackData.animationTime;
					end));
					drawText(obj, getValue('endTime', function()
						return obj.attackData.endTime;
					end));
					drawText(obj, getValue('castFrame', function()
						return obj.attackData.castFrame;
					end));
					drawText(obj, getValue('projectileSpeed', function()
						return obj.attackData.projectileSpeed;
					end));
					drawText(obj, getValue('target', function()
						local handle = obj.attackData.target;
						if handle ~= nil then
							local target = handles[obj.attackData.target];
							if isValidTarget(target) then
								return target.name;
							end
						end
						return "";
					end));
				end
			end
		end);
	end);