BiValues
========
BiValues is a script for Garry's Mod designed to both syncrhonize variables between client and server as well as 
use two-directional binding and variable change callbacks. By default, it supports bindings for some VGUI elements, 
such as text entries, sliders, buttons and labels.

For example, you can use BiValues to bind a variable to a slider, and the variable will be updated when the slider is moved. 
When the variable is changed from elsewhere, the change will be applied to the slider. This variable can also be synchronized with 
the server, so you can have consistent variables between the slider, clientside code and serverside code.

Installation instructions and tutorial coming soon.. Meanwhile, you can view the [Stop Motion Helper](http://github.com/Winded/StopMotionHelper) code, which uses BiValues to easily transfer 
player actions between client, server and VGUI.