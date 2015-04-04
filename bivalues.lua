--[[

The MIT License (MIT)

Copyright (c) 2014 Antton Hytönen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

--]]

if _G["BiValues"] then return; end

---
-- BiValues table definition
---

local BV = {};
BV.BindTypes = {};
BV.Containers = {};

BV.__index = function(table, key)
	if type(key) == "string" and string.sub(key, 1, 1) == "_" then
		local val = rawget(table, key);
		if not val then
			val = getmetatable(table)[key];
		end
		return val;
	else
		local val = rawget(table._NewValues, key);
		if not val then
			val = rawget(table._Values, key);
		end
		if not val and table._RequireValue then
			error(key .. " does not exist");
		end
		return val;
	end
end

BV.__newindex = function(table, key, value)
	if type(key) == "string" and string.sub(key, 1, 1) == "_" then
		rawset(table, key, value);
	else
		table._NewValues[key] = value;
		if table._AutoApply then
			table:_Apply();
		end
	end
end

function BV.New(players, id, settings, defaultValues)

	-- On clientside, we don't need the players parameter, so we shift the parameters.
	if CLIENT then
		defaultValues = settings;
		settings = id;
		id = players;
		players = nil;
	end

	-- Check parameters
	if type(players) == "Player" then
		players = {players};
	end

	if settings.IsPrivate and not game.SinglePlayer() and ((players and #players == 1) or CLIENT) then
		local pl;
		if CLIENT then
			pl = LocalPlayer();
		else
			pl = players[1];
		end
		id = id .. pl:SteamID64();
	end

	local bv = setmetatable({}, BV);
	bv._ID = id;
	bv._Players = players;

	settings = settings or {};
	bv._ReadOnly = settings.ReadOnly or false;
	bv._AutoApply = settings.AutoApply or false;
	bv._UseSync = settings.UseSync or false;
	bv._RequireValue = settings.RequireValue or false;

	bv._Values = {};
	bv._NewValues = {};
	if defaultValues then
		for key, value in pairs(defaultValues) do
			bv._Values[key] = value;
		end
	end

	bv._Bindings = {};
	bv._Listeners = {};

	BV.Containers[id] = bv;

	return bv;

end

function BV.RegisterBindType(name, meta)
	meta.__index = meta;
	BV.BindTypes[name] = meta;
end

function BV.BindToConVar(container, key, convar, settings)
	container:_BindToConVar(key, convar, settings);
end

function BV.UnBindConVar(container, key, convar)
	container:_UnBindConVar(key, convar);
end

function BV:_GetPlayers()
	if CLIENT then
		return {LocalPlayer()};
	end
	return self._Players or player.GetAll();
end

-- Convenience method for returning the first player in the owner list.
function BV:_GetPlayer()
	if CLIENT then
		return LocalPlayer();
	end
	if not self._Players or #self._Players == 0 then
		return nil;
	end
	return self._Players[1];
end

function BV:_Bind(entity, key, type, settings)

	entity.Bindings = entity.Bindings or {};

	for _, binding in pairs(self._Bindings) do
		if binding.Entity == entity and binding.Key == key then
			ErrorNoHalt("Binding " .. entity .. " -> " .. self._ID .. " -> " .. key .. " already exists");
			return;
		end
	end

	if not BV.BindTypes[type] then
		error("Invalid bind type");
		return;
	end
	local bindMeta = BV.BindTypes[type];

	local b = setmetatable({}, bindMeta);
	b.Container = self;
	b.Entity = entity;
	b.Key = key;
	b.Settings = settings or {};

	table.insert(entity.Bindings, b);
	table.insert(self._Bindings, b);

	b:Init();
	local value = self[key];
	if value ~= nil then
		b:SetValue(value);
	end

end

function BV:_BindToConVar(key, convar, settings)

	for _, binding in pairs(self._Bindings) do
		if type(binding.Entity) == "ConVar" and binding.Entity:GetName() == convar:GetName() and binding.Key == key then
			ErrorNoHalt("Binding " .. convar:GetName() .. " -> " .. self._ID .. " -> " .. key .. " already exists");
			return;
		end
	end

	local bindMeta = BV.BindTypes["ConVar"];
	local b = setmetatable({}, bindMeta);
	b.Container = self;
	b.Entity = convar;
	b.Key = key;
	b.Settings = settings or {};
	table.insert(self._Bindings, b);

	b:Init();
	local value = self[key];
	if value ~= nil then
		b:SetValue(value);
	end

end

function BV:_UnBind(entity, key)
	for _, binding in pairs(self._Bindings) do
		if binding.Entity == entity and binding.Key == key then
			binding:Remove();
			table.RemoveByValue(self._Bindings, binding);
			table.RemoveByValue(entity.Bindings, binding);
			return;
		end
	end
end

function BV:_UnBindConVar(key, convar)
	for _, binding in pairs(self._Bindings) do
		if type(binding.Entity) == "ConVar" and binding.Entity:GetName() == convar:GetName() and binding.Key == key then
			binding:Remove();
			table.RemoveByValue(self._Bindings, binding);
			return;
		end
	end
end

function BV:_Listen(key, func)
	local l = {};
	l.Key = key;
	l.Function = func;
	table.insert(self._Listeners, l);
	return l;
end

function BV:_DontListen(listener)
	table.RemoveByValue(self._Listeners, listener);
end

-- Call __newindex so that the given key is placed on _NewValues, marking it as changed.
function BV:_MarkChanged(key)
	self[key] = self[key];
end

function BV:_ApplyFromBind(binding, key, value)
	self._NewValues[key] = value;
	self:_Apply(binding, false);
end

function BV:_ApplySynced(newValues)
	self._NewValues = newValues;
	self:_Apply(nil, true);
end

function BV:_Apply(fromBinding, fromSync)

	local values = self._NewValues;
	self._NewValues = {};
	for key, value in pairs(values) do
		self._Values[key] = value;
	end

	for _, binding in pairs(self._Bindings) do
		local value = values[binding.Key];
		if fromBinding ~= binding and value ~= nil then
			binding:SetValue(value);
		end
	end

	for _, listener in pairs(self._Listeners) do
		local value = values[listener.Key];
		if value ~= nil then
			listener.Function(self, listener.Key, value);
		end
	end

	if not fromSync and self._UseSync then
		net.Start("BiValuesSync");

		net.WriteString(self._ID);

		local syncValues = {};
		for key, value in pairs(values) do
			local typeid = TypeID(value);
			if net.WriteVars[typeid] then
				syncValues[key] = value;
			end
		end
		net.WriteTable(syncValues);

		if SERVER then
			net.Send(self:_GetPlayers());
		else
			net.SendToServer();
		end
	end

end

-- Call the given function, and apply changes afterwards. Good for changing many values while AutoApply is enabled
function BV:_ApplyBulk(func)
	self._AutoApply = false;
	func(self);
	self:_Apply();
	self._AutoApply = true;
end

-- Call a function from _Values and if sync is enabled, call it remotely as well
function BV:_Call(key, fromSync)

	local func = self[key];

	if func and type(func) == "function" then
		func(self, key);
	end

	for _, listener in pairs(self._Listeners) do
		if listener.Key == key then
			listener.Function(self, listener.Key);
		end
	end

	if not fromSync and self._UseSync then
		net.Start("BiValuesCall");

		net.WriteString(self._ID);
		net.WriteString(key);

		if SERVER then
			net.Send(self:_GetPlayers());
		else
			net.SendToServer();
		end
	end

end

function BV._RecvSync(length, player)

	if CLIENT then
		player = LocalPlayer();
	end

	local id = net.ReadString();
	local newValues = net.ReadTable();

	local container = BV.Containers[id];
	if not container then
		ErrorNoHalt("Failed to synchronize; BiValue container not found!");
		return;
	end

	if SERVER then

		if container._ReadOnly then
			Msg("Received call request to read-only container " .. container._ID .. " from player " .. player);
			return;
		end

		local players = table.Copy(container:_GetPlayers());
		
		if players and not table.HasValue(players, player)  then
			Msg("Unauthorized access to container " .. container._ID .. " from player " .. player);
			return;
		end

		-- Broadcast call to any other players owning the container
		table.RemoveByValue(players, player);
		if #players > 0 then
			net.Start("BiValuesSync");
			net.WriteString(container._ID);
			net.WriteTable(newValues);
			net.Send(players);
		end

	end

	container:_ApplySynced(newValues);

end

function BV._RecvCall(length, player)

	if CLIENT then
		player = LocalPlayer();
	end

	local id = net.ReadString();
	local key = net.ReadString();

	local container = BV.Containers[id];
	if not container then
		ErrorNoHalt("Failed to synchronize; BiValue container not found!");
		return;
	end

	if SERVER then

		if container._ReadOnly then
			Msg("Received call request to read-only container " .. container._ID .. " from player " .. player);
			return;
		end

		local players = table.Copy(container:_GetPlayers());

		if players and not table.HasValue(players, player)  then
			Msg("Unauthorized access to container " .. container._ID .. " from player " .. player);
			return;
		end

		-- Broadcast call to any other players owning the container
		table.RemoveByValue(players, player);
		if #players > 0 then
			net.Start("BiValuesCall");
			net.WriteString(container._ID);
			net.WriteString(key);
			net.Send(players);
		end

	end

	container:_Call(key, true);

end

if SERVER then
	util.AddNetworkString("BiValuesSync");
	util.AddNetworkString("BiValuesCall");
end
net.Receive("BiValuesSync", BV._RecvSync);
net.Receive("BiValuesCall", BV._RecvCall);

---
-- Default bind types
---

local VALUE = {};
function VALUE:Init()
	local control = self.Entity;
	local callback = self.Settings.Callback or "OnValueChanged";
	control[callback] = function(control, value)
		self:OnValueChanged(value);
	end
end
function VALUE:Remove()
	local control = self.Entity;
	local callback = self.Settings.Callback or "OnValueChanged";
	control[callback] = function() end
end
function VALUE:OnValueChanged(value)
	local container = self.Container;
	local key = self.Key;
	container:_ApplyFromBind(self, key, value);
end
function VALUE:SetValue(value)
	local control = self.Entity;
	local callback = self.Settings.Callback or "OnValueChanged";
	local valueFunc = self.Settings.ValueFunction or "SetValue";
	local func = control[callback];
	control[callback] = function() end
	control[valueFunc](control, value);
	control[callback] = func;
end
BV.RegisterBindType("Value", VALUE);

local NUMBER = setmetatable({}, VALUE);
function NUMBER:Init()
	self.Settings.Callback = self.Settings.Callback or "OnValueChanged";
	self.Settings.ValueFunction = self.Settings.ValueFunction or "SetValue";
	VALUE.Init(self);
end
function NUMBER:OnValueChanged(value)
	value = tonumber(value);
	if not value then
		value = 0;
	end
	VALUE.OnValueChanged(self, value);
end
BV.RegisterBindType("Number", NUMBER);

local TEXT = setmetatable({}, VALUE);
function TEXT:Init()
	self.Settings.Callback = self.Settings.Callback or "OnChange";
	self.Settings.ValueFunction = self.Settings.ValueFunction or "SetValue";
	local control = self.Entity;
	control[self.Settings.Callback] = function(control)
		self:OnValueChanged(control:GetValue());
	end
end
BV.RegisterBindType("TextEntry", TEXT);

local BUTTON = {};
function BUTTON:Init()
	local control = self.Entity;
	local callback = self.Settings.Callback or "DoClick";
	control[callback] = function()
		self:OnPress();
	end
end
function BUTTON:Remove()
	local control = self.Entity;
	local callback = self.Settings.Callback or "DoClick";
	control[callback] = function() end
end
function BUTTON:OnPress()
	local container = self.Container;
	local key = self.Key;
	container:_Call(key);
end
function BUTTON:SetValue(value)
	-- Do nothing
end
BV.RegisterBindType("Button", BUTTON);

local LABEL = {};
function LABEL:Init()
	-- Do nothing
end
function LABEL:Remove()
	-- Do nothing
end
function LABEL:SetValue(value)
	local control = self.Entity;
	control:SetText(value);
end
BV.RegisterBindType("Label", LABEL);

local VISIBILITY = setmetatable({}, VALUE);
function VISIBILITY:Init()
	local control = self.Entity;
	if not control.OldSetVisible then
		control.OldSetVisible = control.SetVisible;
		control.SetVisible = function(control, value)
			control.OldSetVisible(control, value);
			self:OnValueChanged(value);
		end
	end
	self.Settings.ValueFunction = "SetVisible";
end
BV.RegisterBindType("Visibility", VISIBILITY);

local CHECKBOX = setmetatable({}, VALUE);
function CHECKBOX:Init()
	self.Settings.Callback = self.Settings.Callback or "OnChange";
	self.Settings.ValueFunction = self.Settings.ValueFunction or "SetValue";
	VALUE.Init(self);
end
BV.RegisterBindType("CheckBox", CHECKBOX);

local LISTVIEW = {};
function LISTVIEW:Init()
	-- Do nothing
end
function LISTVIEW:Remove()
	-- Do nothing
end
function LISTVIEW:SetValue(value)
	local control = self.Entity;
	control:ClearSelection();
	control:Clear();
	if value == nil then
		return;
	end
	for k, v in pairs(value) do
		if type(v) == "table" then
			control:AddLine(unpack(v));
		elseif type(v) == "string" then
			control:AddLine(v);
		end
	end
end
BV.RegisterBindType("ListView", LISTVIEW);

local LVSELECT = setmetatable({}, VALUE);
function LVSELECT:Init()
	self.Settings.ColumnID = self.Settings.ColumnID or 1;
	local control = self.Entity;
	control.OnRowSelected = function(control, lineID, line)
		local value = line:GetValue(self.Settings.ColumnID);
		self:OnValueChanged(value);
	end
end
function LVSELECT:Remove()
	local control = self.Entity;
	control.OnRowSelected = function() end
end
function LVSELECT:SetValue(value)
	local control = self.Entity;
	control:ClearSelection();
	local func = control.OnRowSelected;
	control.OnRowSelected = function() end
	for i, line in pairs(control:GetLines()) do
		local v = line:GetValue(self.Settings.ColumnID);
		if v == value then
			control:SelectItem(line);
			break;
		end
	end
	control.OnRowSelected = func;
end
BV.RegisterBindType("ListViewSelect", LVSELECT);

local COMBOBOX = {};
function COMBOBOX:Init()
	-- Do nothing
end
function COMBOBOX:Remove()
	-- Do nothing
end
function COMBOBOX:SetValue(value)
	local control = self.Entity;
	control:Clear();
	if value == nil then
		return;
	end
	for k, v in pairs(value) do
		control:AddChoice(k, v);
	end
end
BV.RegisterBindType("ComboBox", COMBOBOX);

local CBSELECT = setmetatable({}, VALUE);
function CBSELECT:Init()
	local control = self.Entity;
	control.OnSelect = function(control, index, text, data)
		self:OnValueChanged(data);
	end
end
function CBSELECT:Remove()
	local control = self.Entity;
	control.OnSelect = function() end
end
function CBSELECT:SetValue(value)
	local control = self.Entity;
	local func = control.OnSelect;
	control.OnSelect = function() end
	for idx, data in ipairs(control.Data) do
		if data == value then
			control:ChooseOptionID(idx);
			break;
		end
	end
	control.OnSelect = func;
end
BV.RegisterBindType("ComboBoxSelect", CBSELECT);

local CONVAR = setmetatable({}, VALUE);
function CONVAR:Init()
	local convar = self.Entity;
	if type(convar) ~= "ConVar" then
		error("ConVar bind not bound to a convar!");
	end
	self:OnValueChanged(convar:GetString());
	self.CallbackIdentifier = convar:GetName() .. math.random(1, 10000);
	cvars.AddChangeCallback(convar:GetName(), function(name, oldValue, newValue)
		self:OnValueChanged(newValue);
	end, self.CallbackIdentifier);
end
function CONVAR:Remove()
	local convar = self.Entity;
	cvars.RemoveChangeCallback(convar:GetName(), self.CallbackIdentifier);
end
function CONVAR:OnValueChanged(value)
	local container = self.Container;
	local key = self.Key;
	local valueType = self.Settings.ValueType or "string";
	if valueType == "number" then
		value = tonumber(value);
	elseif valueType == "boolean" then
		value = tobool(value);
	else
		value = tostring(value);
	end
	if value == nil then
		return;
	end
	container:_ApplyFromBind(self, key, value);
end
function CONVAR:SetValue(value)
	local convar = self.Entity;
	cvars.RemoveChangeCallback(convar:GetName(), self.CallbackIdentifier);
	local valueType = self.Settings.ValueType or "string";
	if value ~= nil then
		RunConsoleCommand(convar:GetName(), tostring(value));
	end
	cvars.AddChangeCallback(convar:GetName(), function(name, oldValue, newValue)
		self:OnValueChanged(newValue);
	end, self.CallbackIdentifier);
end
BV.RegisterBindType("ConVar", CONVAR);

BV.ValueBind = VALUE;
BV.NumberBind = NUMBER;
BV.TextBind = TEXT;
BV.ButtonBind = BUTTON;
BV.LabelBind = LABEL;
BV.VisibilityBind = VISIBILITY;
BV.CheckBoxBind = CHECKBOX;
BV.ListViewBind = LISTVIEW;
BV.ListViewSelectBind = LVSELECT;
BV.ComboBoxBind = COMBOBOX;
BV.ComboBoxSelectBind = CBSELECT;
BV.ConVarType = CONVAR;

---
-- Meta table setup
---

local ENT = FindMetaTable("Entity");

function ENT:Bind(container, key, type)
	container:_Bind(self, key, type);
end

function ENT:UnBind(container, key)
	container:_UnBind(self, key);
end

if CLIENT then

local PANEL = FindMetaTable("Panel");

function PANEL:Bind(container, key, type, settings)
	container:_Bind(self, key, type, settings);
end

function PANEL:UnBind(container, key)
	container:_UnBind(self, key);
end

end

---
-- Finally, put the table to the global scope, and make sure the clients download this script
---

AddCSLuaFile();
_G.BiValues = BV;