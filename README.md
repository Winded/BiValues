BiValues
========
BiValues is a script for Garry's Mod designed to both syncrhonize variables between client and server as well as 
use two-directional binding and variable change callbacks. By default, it supports bindings for some VGUI elements, 
such as text entries, sliders, buttons and labels.

For example, you can use BiValues to bind a variable to a slider, and the variable will be updated when the slider is moved. 
When the variable is changed from elsewhere, the change will be applied to the slider. This variable can also be synchronized with 
the server, so you can have consistent variables between the slider, clientside code and serverside code.

## How it works
The BiValues framework consists of three different object types: containers, bindings and listeners.

 - _Containers_ are the core objects that contain your variables. They handle syncrhonizing between clients and server as well as interaction with bindings and listeners. Containers have unique IDs to identify them within the network and are stored in _BiValues.Containers_
 - _Bindings_ handle the transmission of a variable to and from entities, VGUI controls or any kind of other interactable objects. Bind types determine the functionality of a binding to make sure it handles the transmission as it's supposed to.
 - _Listeners_ are one-way callbacks that are hooked to a single variable in the container. They are used to perform any actions required whenever a variable is changed in the container, either from binding, synchronizing or from code.

### Container ownership
Starting from version 0.2, containers are not player-specific anymore, and are stored in _BiValues.Containers_ instead of _Player.BiValueContainers_. Instead, containers now have a list of players as owners, which can be received (and edited) from __GetPlayers()_ function. Only the owners of a container receive sync messages from the server, and are the only ones allowed to send sync messages to the server. When a container doesn't have any owner, all players are the owners of the container.

If you set _IsPrivate_ setting to true on a container, and set a single player as the owner of the container, the container becomes "private" meaning the ID of the container is appended with the SteamID of the player, making sure the container is unique and for that player only. You can also do this manually, but the _IsPrivate_ setting can be used for convenience.

On clientside, the ownership of a container is irrelevant and not used, so the _BiValues.New_ function does not take the _players_ parameter.

### Visual representation
TBD

## Installation
You can either copy the _bivalues.lua_ file to lua/autorun in your addon folder, or you can clone the repository to lua/bivalues and then include the lua script in your own autorun script. If your project has its own git repository, you can add this as a submodule. Be sure to add the _.git_ folder and _README.md_ to the ignore list in _addon.json_, as the workshop publisher won't accept them.

## Usage
Before BiValues can be used, a container and required listeners and bindings need to be created.

### Initialization
On client, we can do this setup just before we build the UI or entities that are used for bindings. _InitPostEntity_ is a good place to setup as we have the player entity available if we need it.

```lua
hook.Add("InitPostEntity", "BiValuesSetup", function()

    local player = LocalPlayer();

	-- Default values to set when creating the container.
	local defaults = {foo = "bar", hammertime = false};
	local bivalues = BiValues.New("Example", {IsPrivate = true, AutoApply = true, UseSync = true}, defaults);

	-- Adding a listener to a variable
	bivalues:_Listen("hammertime", function(container, key, value)
		if value then
			print("It's hammer time!");
		end
	end);

	-- Store reference to our container for easy access
	player.ExampleData = bivalues;

	BuildVGUI();

end);
```

On server, we can use _PlayerInitialSpawn_ for setup if we need a player (or players) for our container.

```lua
hook.Add("PlayerInitialSpawn", "BiValuesSetup", function(player)

    -- Default values to set when creating the container.
	local defaults = {foo = "bar", hammertime = false};
	local bivalues = BiValues.New(player, "Example", {IsPrivate = true, AutoApply = true, UseSync = true}, defaults);

	-- Adding a listener to a variable
	bivalues:_Listen("hammertime", function(container, key, value)
		if value then
			print("It's hammer time!");
		end
	end);

	-- Store reference to our container for easy access.
	player.ExampleData = bivalues;

	-- Serverside bindings can be created here

end);
```

### Binding
To bind entities or VGUI elements to variables, just use the _Bind_ function as demonstrated below. Do note that using an incorrect bind type will most probably cause problems.

```lua
function BuildVGUI()

    local bivalues = LocalPlayer().ExampleData;

	local frame = vgui.Create("DFrame");
	frame:SetTitle("BiValues example");
	frame:SetSize(75, 80);

	local text = vgui.Create("DTextEntry", frame);
	text:SetPos(5, 30);
	text:SetSize(65, 20);
	text:Bind(bivalues, "foo", "TextEntry");

	local checkbox = vgui.Create("DCheckBox", frame);
	checkbox:SetPos(5, 55);
	checkbox:SetText("Hammer time?");
	checkbox:SizeToContents();
	checkbox:Bind(bivalues, "hammertime", "CheckBox");

	frame:MakePopup();

end
```

As you can see, with BiValues we can easily seperate our visual interface code from our logical code.

### Accessing variables
So now we have the container, we have bound some VGUI elements to our variables, and we have also added a listener. All variables are acting like they're members of the container that we created, so they are very easy to access in code.

```lua
concommand.Add("bv_test", function(player, cmd, args)

    local bivalues = player.ExampleData;

	-- Getting variables
	if bivalues.hammertime then
		print("Can't touch this");
	end
	print("Foo is currently " .. bivalues.foo);

	-- Setting variables
	bivalues.hammertime = false;
	bivalues.foo = "foobar";
	-- This is required if AutoApply setting is not set to true
	bivalues:_Apply();

end);
```

### Putting it all together
You can try combining all of the things above to get a working example of BiValues. The _example.lua_ script is a kind of a Advanced Bone tool rip-off that uses BiValues, so you can look into it for a more complete example of using BiValues.

## Function variables
You can assing functions as variables into containers. These functions can then be called using the container's _\_Call_ function, or through a binding, like the Button binding. This call then triggers listeners that are listening for the variable, and also calls the function on both server and client if syncrhonizing is enabled.

```lua
local function Foo(container, key)
    local player = container:_GetPlayer();
	print("Foo called for " .. player:Nick());
end

if CLIENT then

hook.Add("InitPostEntity", "BiValuesSetup", function()

	local player = LocalPlayer();

	local defaults = {Foo = Foo};
	local bivalues = BiValues.New("Example", {IsPrivate = true, AutoApply = true, UseSync = true}, defaults);

	bivalues:_Listen("Foo", function(container, key, value)
		print("Foo was called");
	end);

	player.ExampleData = bivalues;

	local btn = vgui.Create("DButton");
	btn:SetText("Press me!");
	btn:Bind(bivalues, "Foo", "Button");

end);

elseif SERVER then

hook.Add("PlayerInitialSpawn", "BiValuesSetup", function(player)

	local defaults = {Foo = Foo};
	local bivalues = BiValues.New(player, "Example", {IsPrivate = true, AutoApply = true, UseSync = true}, defaults);

	bivalues:_Listen("Foo", function(container, key, value)
		print("Foo was called");
	end);

	player.ExampleData = bivalues;

end);

concommand.Add("foo", function(player, cmd, args)
	local bivalues = player.ExampleData;
	bivalues:_Call("Foo");
end);

end
```

## Bind types
Bind types determine the functionality of bindings so that they are handling the transmission of variables correctly for specific types of entities or VGUI controls. There are default bind types for generic VGUI controls that you may often use, but it is also possible and fairly easy to create your own bind types.

### Default types
For best understanding of default bind types, please look into the code itself. Here are the basic types in a nutshell.

 - **Value** - Generic binding for value-based VGUI controls
 - **Number** - Generic binding for numeric value VGUI controls, such as sliders and numberwangs
 - **TextEntry** - Binding for _DTextEntry_
 - **Button** - Binding for _DButton_, only useful for function variables
 - **Visibility** - Binding for a boolean variable to show/hide VGUI panels.
 - **CheckBox** - Binding for _DCheckBox_
 - **ListView** - Binding for the contents of _DListView_. This should be a table either in form _{"line1", "line2"}_ or _{{"column1", "column2"}, {"column1", "column2"}}_
 - **ListViewResult** - Binding for the selected item of _DListView_

### Creating custom types
TBD