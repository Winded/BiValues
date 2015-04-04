
--[[
	Example tool for demonstrating BiValues functionality.
]]

TOOL.Name = "BiValues Example Tool";
TOOL.Category = "Poser";
TOOL.Command = nil;
TOOL.ConfigName = "";

local DefaultValues = {
	PosX = 0, PosY = 0, PosZ = 0,
	AngP = 0, AngY = 0, AngR = 0,
	ScaleX = 1, ScaleY = 1, ScaleZ = 1,
};

local ManipulationKeys = {
	"PosX", "PosY", "PosZ",
	"AngP", "AngY", "AngR",
	"ScaleX", "ScaleY", "ScaleZ",
};

local function EntityChanged(container, key, value)

	if not IsValid(value) then
		container.BoneChoices = {};
		container.Bone = -1;
		container:_ApplyBulk(function()
			for key, val in pairs(DefaultValues) do
				container[key] = 0;
			end
		end);
		return;
	end

	local entity = value;
	local bones = {};
	for b = 0, entity:GetBoneCount() - 1 do
		local name = entity:GetBoneName(b);
		if name ~= "__INVALIDBONE__" then
			bones[name] = b;
		end
	end

	container.BoneChoices = bones;
	container.Bone = -1;
	container:_ApplyBulk(function()
		for key, val in pairs(DefaultValues) do
			container[key] = 0;
		end
	end);

end

local function BoneChanged(container, key, value)
	local entity = container.Entity;
	local bone = value;
	if not IsValid(entity) or not bone or bone == -1 then
		return;
	end

	container:_ApplyBulk(function()
		local manPos = entity:GetManipulateBonePosition(bone);
		local manAng = entity:GetManipulateBoneAngles(bone);
		local manScale = entity:GetManipulateBoneScale(bone);

		container.PosX = manPos.x;
		container.PosY = manPos.y;
		container.PosZ = manPos.z;
		container.AngP = manAng.p;
		container.AngY = manAng.y;
		container.AngR = manAng.r;
		container.ScaleX = manScale.x;
		container.ScaleY = manScale.y;
		container.ScaleZ = manScale.z;
	end);

end

local function Manipulated(container, key, value)
	local entity = container.Entity;
	local bone = container.Bone;
	if not IsValid(entity) or not bone or bone == -1 then
		return;
	end

	local manPos = Vector(container.PosX, container.PosY, container.PosZ);
	local manAng = Angle(container.AngP, container.AngY, container.AngR);
	local manScale = Vector(container.ScaleX, container.ScaleY, container.ScaleZ);

	entity:ManipulateBonePosition(bone, manPos);
	entity:ManipulateBoneAngles(bone, manAng);
	entity:ManipulateBoneScale(bone, manScale);
end

local function CreateContainer(player)

	if player.BVET then
		return;
	end

	local defaults = {
		Entity = nil,
		BoneChoices = {},
		Bone = nil,
		PosX = 0, PosY = 0, PosZ = 0,
		AngP = 0, AngY = 0, AngR = 0,
		ScaleX = 0, ScaleY = 0, ScaleZ = 0,
	};

	if SERVER then
		defaults.Reset = function(container, key)
			container:_ApplyBulk(function()
				for key, val in pairs(DefaultValues) do
					container[key] = val;
				end
			end);
		end
	end

	local data;
	if SERVER then
		data = BiValues.New(player, "BVET", {IsPrivate = true, UseSync = true, AutoApply = true}, defaults);
	else
		data = BiValues.New("BVET", {IsPrivate = true, UseSync = true, AutoApply = true}, defaults);
	end

	if SERVER then
		data:_Listen("Entity", EntityChanged);
		data:_Listen("Bone", BoneChanged);

		for key, val in pairs(DefaultValues) do
			data:_Listen(key, Manipulated);
		end
	end

	if CLIENT then
		for key, val in pairs(DefaultValues) do
			data:_BindToConVar(key, CreateClientConVar("bvet_" .. key:lower(), val, false), {ValueType = "number"});
		end
	end

	player.BVET = data;

end

function TOOL:LeftClick(trace)

	if not IsValid(trace.Entity) then
		return false;
	end
	if CLIENT then
		return true;
	end

	local data = self:GetOwner().BVET;
	data.Entity = trace.Entity;
	data.Bone = data.Entity:TranslatePhysBoneToBone(trace.PhysicsBone);
	return true;

end

function TOOL:RightClick(trace)

	if CLIENT then
		return true;
	end

	local data = self:GetOwner().BVET;
	data.Entity = Entity(-1);
	return true;

end

function TOOL:Deploy()
	local player = self:GetOwner();
	if not player.BVET then
		CreateContainer(player);
	end
end

if CLIENT then

language.Add("tool.example.name", "BiValues Example Tool");
language.Add("tool.example.desc", "Advanced bone tool -like tool to demonstrate BiValues functionality");
language.Add("tool.example.0", "Left click to select entities for manipulation.");

function TOOL.BuildCPanel(cpanel)

	local player = LocalPlayer();
	if not player.BVET then
		CreateContainer(player);
	end
	local data = player.BVET;

	local boneBox = vgui.Create("DComboBox", cpanel);
	boneBox:SetValue("Select bone");
	cpanel:AddItem(boneBox);
	boneBox:Bind(data, "BoneChoices", "ComboBox");
	boneBox:Bind(data, "Bone", "ComboBoxSelect");

	for _, key in pairs(ManipulationKeys) do
		local sliderTitle = vgui.Create("DLabel", cpanel);
		sliderTitle:SetText(key);
		sliderTitle:SizeToContents();
		cpanel:AddItem(sliderTitle);
		local slider = vgui.Create("Slider", cpanel);
		slider:SetMinMax(-500, 500);
		slider:SetValue(0);
		cpanel:AddItem(slider);
		slider:Bind(data, key, "Number");
	end

	local resetBtn = vgui.Create("DButton", cpanel);
	resetBtn:SetText("Reset");
	resetBtn:SetSize(120, 30);
	cpanel:AddItem(resetBtn);
	resetBtn:Bind(data, "Reset", "Button");

end

end