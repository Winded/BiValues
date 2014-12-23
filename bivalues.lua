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

---
-- BiValues table definition
---

local BV = {};
BV.BindTypes = {};

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

function BV.New(player, id, settings, defaultValues)

	local bv = setmetatable({}, BV);
	bv._ID = id;
	bv._Player = player;

	settings = settings or {};
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

	player.BiValueContainers = player.BiValueContainers or {};
	player.BiValueContainers[id] = bv;

	return bv;

end

function BV.RegisterBindType(name, meta)
	meta.__index = meta;
	BV.BindTypes[name] = meta;
end

function BV:_Bind(entity, key, type, settings)

	entity.Bindings = entity.Bindings or {};

	if entity.Bindings[key] then
		ErrorNoHalt("Entity already has a binding for " .. key .. "!");
		return;
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

	entity.Bindings[key] = b;
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
			entity.Bindings[key] = nil;
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
			net.Send(self._Player);
		else
			net.SendToServer();
		end
	end

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
			net.Send(self._Player);
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

	if not player.BiValueContainers or not player.BiValueContainers[id] then
		ErrorNoHalt("Failed to synchronize; BiValue container not found!");
		return;
	end

	local container = player.BiValueContainers[id];
	container:_ApplySynced(newValues);

end

function BV._RecvCall(length, player)

	if CLIENT then
		player = LocalPlayer();
	end

	local id = net.ReadString();
	local key = net.ReadString();

	if not player.BiValueContainers or not player.BiValueContainers[id] then
		ErrorNoHalt("Failed remote call; BiValue container not found!");
		return;
	end

	local container = player.BiValueContainers[id];
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
	control.OldSetVisible = control.SetVisible;
	control.SetVisible = function(control, value)
		control.OldSetVisible(control, value);
		self:OnValueChanged(value);
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

BV.ValueBind = VALUE;
BV.NumberBind = NUMBER;
BV.TextBind = TEXT;
BV.ButtonBind = BUTTON;
BV.LabelBind = LABEL;
BV.CheckBoxBind = CHECKBOX;

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