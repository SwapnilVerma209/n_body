# n_body
This is a n-body simulation made with the [Godot](https://godotengine.org/)
game engine. This simulation accounts for special relativistic and some
general relativistic effects. This simulation includes gravitational and
electromagnetic interactions between non-rotating spheres of uniform mass
density and uniform charge density. This simulation is currently a direct
n-body, but I have plans in the future to optimize this using the Barnes-Hutt
algorithm. In the future, I may include rotational mechanics. As for the effects
of rotation on the gravitational and electromagnetic fields, I may not include
that, considering the complexity. I also have plans to make this simulation
more user-friendly, with a proper UI. Please let me know if you find any bugs!

## How to Use
For now, there is no UI for creating simulations. You need to modify the code
to add bodies manually. For this, you will need to clone this repository and
open it in the Godot editor
([compiled](https://docs.godotengine.org/en/stable/contributing/development/compiling/index.html)
for double precision using the parameter `precision=double`). Then, you need to
go into the file simulation.gd and the function _ready().

To modify the simulation's spaital precision, modify the call:
```
Global.set_precision(3)
```
Double precision floats have 15 digits of reliable precision. The first argument
determines how many of these digits are on the right of the decimal point in
coordinate systems. If this number is smaller, the simulation space will be
bigger, but it will be less precise. At 6, this means that the smallest possible
distance is 10^-6 units, and the largest is 10^10 - 10^-6 units.

To modify the units used in calculations, modify the call:
```
Global.set_scales("proton_radius", "atomic_time", "proton_mass", \
			"elementary_charge")
```
These units can be found in global.gd. The first unit determines the space
untis. whatever you set here will be the default space unit. For example, the
coordinate (1, 0, 0) will be 1 proton radius away from the origin in this
simulation. The second unit determines time. Using larger units will speed the
simulation up, but at the cost of precision. The third determines mass. The
fourth represents electric charge. What units are ideal depends on the scale of
the simulation.

Now you can start adding bodies. An example is provided. You need to use the
function
```
func _add_body(label: String, mass_amount: float, mass_unit: String, \
		charge_amount: float, charge_unit: String,\
		radius_amount: float, rad_space_unit: String, pos_amount: Vector3, \
		pos_space_unit: String, vel_amount: Vector3, vel_space_unit: String, \
		vel_time_unit: String, color: Vector3=Vector3(255.0, 255.0, 255.0),
		is_collidable=true) \
```
The label is the name of the body, and will be visible above it. The parameters
up to color specify the initial conditions of the body. You can specify values
using any of the units in global.gd, and they will be automatically converted
to the units of the simulation. color takes a 3Vector representing a RGB value.
If no color is specified, it is set to pure white. is_collidable determines if
your body can collide with other bodies (all bodies will collide with black
holes). With this, loops, and random number generation, you can go crazy and
create all kinds of universes!

## Moving around in the simulation
Movement will start slow, but accelerate to high speeds as long as you keep
holding the movement keys. This is to allow both slow, precise movements and
fast movements. Will add mouse camera controls later.

### Controls
W - Move forward

A - Move left

S - Move backward

D - Move right

Space bar - Move up

Left shift - Move down

Up arrow - Look up

Left arrow - Look left

Down arrow - Look down

Right arrow - Look right
