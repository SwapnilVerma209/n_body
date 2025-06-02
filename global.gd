extends Node

const NUM_DIGITS := 15

const DEFAULT_TIMESTEP := 1e-3
const MIN_DISPLAY_RADIUS := 0.1

# Fundamental constants in SI units
const GRAV_CONST_SI := 6.67408e-11 ## Units: m^3 kg^-1 s^-2
const COULOMB_CONST_SI := 8.9875517862e9 ## Units: N m^2 C^-2 (or kg m^3 C^-2 s^-2)
const LIGHT_SPEED_SI := 299792458.0 ## Units: m / s


# Scales of various units
const SPACE_SCALES := {
	"proton_radius" : 8.77e-16,
	"electron_radius" : 2.8179403205e-15,
	"bohr_radius" : 5.29177210544e-11,
	"nanometer" : 1e-9,
	"micrometer" : 1e-6,
	"millimeter" : 0.001,
	"centimeter" : 0.01,
	"meter" : 1.0,
	"kilometer" : 1000.0,
	"megameter" : 1e6,
	"lunar_radius" : 1.7374e6,
	"earth_radius" : 6.3710e6,
	"jupiter_radius" : 6.9911e7,
	"solar_radius" : 6.957e8,
	"astronomical_unit" : 1.495978707e11,
	"light_year" : 9460730472580800.0,
	"parsec" : 3.085677581e16,
	"milky_way_radius" : 43700.0 * 9460730472580800.0,
	"observable_universe_radius" : 4.4e26
} # Space units expressed in m
const TIME_SCALES := {
	"nanosecond" : 1e-9,
	"microsecond" : 1e-6,
	"millisecond" : 0.001,
	"second" : 1.0,
	"minute" : 60.0,
	"hour" : 3600.0,
	"day" : 24.0 * 3600.0,
	"year" : 365.25 * 24.0 * 3600.0,
	"decade" : 10.0 * 365.25 * 24.0 * 3600.0,
	"century" : 100.0 * 365.25 * 24.0 * 3600.0,
	"millenia" : 1000.0 * 365.25 * 24.0 * 3600.0,
	"megayear" : 1e6 * 365.25 * 24.0 * 3600.0,
	"gigayear" : 1e9 * 365.25 * 24.0 * 3600.0
} # Time units expressed in s
const MASS_SCALES := {
	"electron_mass" : 9.1093837139e-31,
	"proton_mass" : 1.67262192595e-27,
	"nanogram" : 1e-12,
	"microgram" : 1e-9,
	"gram" : 0.001,
	"kilogram" : 1.0,
	"tonne" : 1000.0,
	"lunar_mass" : 7.346e22,
	"earth_mass" : 5.9722e24,
	"jupiter_mass" : 1.89813e27,
	"solar_mass" : 1.988416e30,
	"milky_way_mass" : 2.29e42,
	"observable_universe_mass" : 3.5e54
} # Mass units expressed in kg
const CHARGE_SCALES := {
	"coulomb" : 1.0,
	"elementary_charge" : 1.602176634e-19
}

var precision_digits := 3
var max_error_power := -precision_digits
var max_space_error := pow(10, max_error_power)
var max_sim_dist := pow(10, NUM_DIGITS - precision_digits)
		## The maximum distance along any given coordinate axis in the simulation
var max_axis_dist := max_sim_dist / sqrt(3.0)

# Names of the chosen units, defaulted to SI
var space_unit := "meter"
var time_unit := "second"
var mass_unit := "kilogram"
var charge_unit := "coulomb"

# Fundamental constants default to SI units
var grav_const = GRAV_CONST_SI
var coulomb_const = COULOMB_CONST_SI
var light_speed = LIGHT_SPEED_SI

# Bodies and escape velocities are capped at this speed to prevent
# infinities. When escape velocities reach this, gravitational fields are set to
# 0.
var max_speed = (1.0 - max_space_error) * light_speed

func set_precision(precision: int) -> void:
	if precision < 0:
		precision = 0
	elif precision > NUM_DIGITS:
		precision = NUM_DIGITS
	precision_digits = precision
	max_error_power = -precision
	max_space_error = pow(10, max_error_power)
	max_speed = (1.0 - max_space_error) * light_speed
	max_sim_dist = pow(10, NUM_DIGITS - precision_digits)
		## The maximum distance along any given coordinate axis in the simulation
	max_axis_dist = max_sim_dist / sqrt(3.0)

func set_scales(space_u, time_u, mass_u, charge_u) -> void:
	space_unit = space_u
	time_unit = time_u
	mass_unit = mass_u
	charge_unit = charge_u
	_set_fund_consts()

func _set_fund_consts() -> void:
	grav_const = GRAV_CONST_SI * (SPACE_SCALES[space_unit] ** -3.0) * \
		MASS_SCALES[mass_unit] * (TIME_SCALES[time_unit] ** 2.0)
	coulomb_const = COULOMB_CONST_SI * (MASS_SCALES[mass_unit] ** -1.0) * \
			(SPACE_SCALES[space_unit] ** -3.0) * \
			(CHARGE_SCALES[charge_unit] ** 2.0) * \
			(TIME_SCALES[time_unit] ** 2.0)
	light_speed = LIGHT_SPEED_SI * \
		(TIME_SCALES[time_unit] / SPACE_SCALES[space_unit])
	max_speed = (1.0 - max_space_error) * light_speed

# Lorentz transformation functions
func lorentz_factor(velocity: Vector3) -> float:
	if velocity.length() > max_speed:
		velocity = max_speed * velocity.normalized()
	var speed := velocity.length()
	return 1.0 / sqrt(1.0 - (speed / light_speed)**2)

func lorentz_fact_recip(velocity: Vector3) -> float:
	if velocity.length() > max_speed:
		velocity = max_speed * velocity.normalized()
	var speed := velocity.length()
	return sqrt(1.0 - (speed / light_speed)**2)

func lorentz_transform_space(position: Vector3, velocity: Vector3, time: float) \
		-> Vector3:
	if velocity.is_zero_approx():
		return position
	if velocity.length() > max_speed:
		velocity = max_speed * velocity.normalized()
	var pos_parallel := position.project(velocity)
	var pos_orthogonal := position - pos_parallel
	return lorentz_factor(velocity) * (pos_parallel - velocity * time) + \
			pos_orthogonal

func lorentz_transform_time(time: float, position: Vector3, velocity: Vector3) \
		-> float:
	if velocity.is_zero_approx():
		return time
	if velocity.length() > max_speed:
		velocity = max_speed * velocity.normalized()
	var pos_parallel := position.project(velocity)
	return lorentz_factor(velocity) * \
			(time - (pos_parallel.dot(velocity) / light_speed**2))

func relativistic_vel_add(vel1: Vector3, vel2_prime: Vector3) -> Vector3:
	if vel1.is_zero_approx():
		return vel2_prime
	if vel1.length() > max_speed:
		vel1 = max_speed * vel1.normalized()
	if vel2_prime.length() > max_speed:
		vel2_prime = max_speed * vel2_prime.normalized()
	var vel2_prime_par := vel2_prime.project(vel1)
	var vel2_prime_orth := vel2_prime - vel2_prime_par
	var vel = (vel2_prime_par + vel1 + lorentz_fact_recip(vel1) * vel2_prime_orth) \
		/ (1.0 + (vel2_prime_par.dot(vel1) / light_speed**2))
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	return vel

func wrap_around_pos(position: Vector3) -> Vector3:
	var new_position := position
	if position.x > max_axis_dist:
		var diff := position.x - max_axis_dist
		new_position.x = -max_axis_dist + diff
	elif position.x < -max_axis_dist:
		var diff := -max_axis_dist - position.x
		new_position.x = max_axis_dist - diff
	if position.y > max_axis_dist:
		var diff := position.y - max_axis_dist
		new_position.y = -max_axis_dist + diff
	elif position.y < -max_axis_dist:
		var diff := -max_axis_dist - position.y
		new_position.y = max_axis_dist - diff
	if position.z > max_axis_dist:
		var diff := position.z - max_axis_dist
		new_position.z = -max_axis_dist + diff
	elif position.z < -max_axis_dist:
		var diff := -max_axis_dist - position.z
		new_position.z = max_axis_dist - diff
	return new_position
