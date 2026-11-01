extends Node3D
## Hold Course - mobile-first vertical slice. Builds the whole world in code.
## The ship stays near z = 0 and only moves sideways / up-down; the world rushes toward it.

const BASE_SPEED := 83.0          ## m/s  (~300 km/h)
const MAX_SPEED := 100.0          ## m/s  (~360 km/h) reached gently over a long run
const VIEW_DIST := 240.0          ## how far ahead rocks are spawned
const SHIP_RADIUS := 0.55
const SAVE_PATH := "user://hold_course.cfg"
const STREAK_COUNT := 140
const STAR_COUNT := 260
const ROCK_VARIANTS := 6
## 2026-11-01 (Daniel): asteroids removed entirely - pure flying, no obstacles.
## Flip to true to bring back rock spawning, rendering, collision and crash/restart.
const OBSTACLES_ENABLED := false

## 2026-11-01 (Daniel): core loop = fly through neon portals for points, with a combo.
const PORTAL_POOL := 6            ## ring nodes recycled (never created/freed mid-run)
const PORTAL_SPACING := 105.0     ## metres between rings (~1.3 s at 300 km/h)
const PORTAL_RADIUS := 3.5        ## ring size (centre of the glowing tube)
const PORTAL_HIT_RADIUS := 3.4    ## ship centre must pass within this of the ring centre
const PORTAL_MAX_STEP := 13.0     ## max sideways/up-down change between consecutive rings
const PORTAL_RANGE := Vector2(10.0, 7.5) ## rings stay inside the steerable area (ship bounds 14 x 11)
const PORTAL_POINTS := 100
const COMBO_MAX := 8              ## multiplier cap
const PORTAL_COLORS := [Color(0.1, 0.95, 1.0), Color(1.0, 0.2, 0.85), Color(1.0, 0.9, 0.15), Color(0.35, 1.0, 0.45)]

## 2026-11-01 (Daniel): camera option - CHASE (behind the ship) or COCKPIT (pilot POV),
## with a smooth fly-in / fly-out transition. Toggle: VIEW button (top-right), C / V keys,
## or the CHASE / COCKPIT choice on the start screen. Saved with the best scores.
const VIEW_TRANSITION := 0.7      ## seconds for the chase <-> cockpit camera move
const VIEW_SWAP_AT := 0.86        ## eased progress where the hull hides and the cockpit appears
const CHASE_OFFSET := Vector3(0, 1.45, 4.8)
const HEAD_OFFSET := Vector3(0, 0.12, 0.05)  ## pilot's eye, relative to the ship centre (unscaled)
const COCKPIT_FOV_ADD := 6.0      ## a touch wider inside so the canopy frame fits
const COCKPIT_SHAKE := 0.45       ## camera shake is reduced in the cockpit

class Portal:
	var node: Node3D
	var mats: Array[StandardMaterial3D] = []
	var alphas: Array[float] = []
	var color := Color.WHITE
	var phase := 0 ## 0 idle, 1 incoming, 2 burst (hit), 3 passed (missed)
	var t := 0.0

enum State { ATTRACT, FLYING }

var state := State.ATTRACT
var ship: HoldShip
var cam: Camera3D
var speed := BASE_SPEED
var distance_m := 0.0
var best_m := 0.0
var crashes := 0
var rng := RandomNumberGenerator.new()

# spawning
var rock_meshes: Array[Mesh] = []
var rock_mat: StandardMaterial3D
var rocks: Array[HoldRock] = []
var travel_since_wave := 0.0
var gap := Vector2.ZERO
var prev_gap := Vector2.ZERO

# juice
var streaks: MultiMesh
var streak_data: Array[Vector3] = [] # x, y, z per streak (world)
var fov_base := 70.0
var fov_kick := 0.0
var shake := 0.0
var flash_rect: ColorRect
var crash_label: Label
var crash_label_t := 0.0

# hud
var dist_label: Label
var best_label: Label
var speed_label: Label
var overlay: Control
var tap_label: Label
var overlay_t := 0.0

# audio
var crash_player: AudioStreamPlayer
var wind_player: AudioStreamPlayer

# portals / score
var portals: Array[Portal] = []
var last_portal_z := 0.0
var portal_path := Vector2.ZERO
var portal_color_i := 0
var score := 0
var best_score := 0
var combo := 0
var portals_hit := 0
var portals_missed := 0
var score_label: Label
var combo_label: Label
var pop_label: Label
var pop_t := 0.0
var combo_bump := 0.0
var tones: HoldPortalTones  ## 2026-11-01: soothing melodic portal tones (scripts/portal_tones.gd)

# camera view
var view_cockpit := false         ## chosen view (target of the transition)
var view_blend := 0.0             ## 0 = chase, 1 = cockpit (linear progress; eased when used)
var view_inside := false          ## cockpit interior currently shown (exterior hull hidden)
var cockpit: HoldCockpit
var ship_parts: Array[Node3D] = []
var view_btn: Panel
var view_btn_icon: Control
var view_mode_label: Label
var view_btn_bump := 0.0
var pick_chase: Panel
var pick_cockpit: Panel
var _style_on: StyleBoxFlat
var _style_off: StyleBoxFlat

var _js_t := 0.0
var _best_save_t := 0.0

func _ready() -> void:
	add_to_group("game")
	rng.randomize()
	_load_best()
	_build_env()
	_build_ship()
	_build_cockpit()
	if OBSTACLES_ENABLED:
		_build_rocks_assets()
	_build_streaks()
	_build_stars()
	_build_portals()
	_build_hud()
	_build_audio()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	_reset_field(true)
	_reset_portals()
	_apply_view_ui()
	_web_setup()

# ---------------------------------------------------------------- world build

func _build_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 35, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.92, 0.82)
	sun.shadow_enabled = false
	add_child(sun)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.5)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.03, 0.08)
	env.fog_density = 0.009
	we.environment = env
	add_child(we)

func _build_ship() -> void:
	ship = HoldShip.new()
	ship.name = "Ship"
	ship.scale = Vector3.ONE * 0.85
	add_child(ship)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.8, 0.85, 0.95)
	body_mat.metallic = 0.3
	body_mat.roughness = 0.4

	var hull := MeshInstance3D.new()
	var hull_mesh := PrismMesh.new()
	hull_mesh.size = Vector3(0.9, 1.8, 0.2) # triangle base, length, thickness
	hull.mesh = hull_mesh
	hull.rotation_degrees = Vector3(-90, 0, 0)
	hull.material_override = body_mat
	ship.add_child(hull)
	ship_parts.append(hull)

	var wing := MeshInstance3D.new()
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(2.2, 0.06, 0.5)
	wing.mesh = wing_mesh
	wing.position = Vector3(0, -0.05, 0.45)
	wing.material_override = body_mat
	ship.add_child(wing)
	ship_parts.append(wing)

	# small tinted canopy bubble on top of the hull: the cockpit the camera flies into
	var canopy := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.5
	cm.height = 1.0
	cm.radial_segments = 12
	cm.rings = 6
	canopy.mesh = cm
	canopy.scale = Vector3(0.2, 0.12, 0.42)
	canopy.position = Vector3(0, 0.08, 0.05)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.2, 0.32)
	glass.metallic = 0.7
	glass.roughness = 0.15
	glass.emission_enabled = true
	glass.emission = Color(0.0, 0.22, 0.3)
	canopy.material_override = glass
	ship.add_child(canopy)
	ship_parts.append(canopy)

	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(0.4, 0.85, 1.0)
	for side in [-1.0, 1.0]:
		var eng := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.22, 0.1, 0.08)
		eng.mesh = em
		eng.position = Vector3(0.45 * side, -0.03, 0.72)
		eng.material_override = glow_mat
		ship.add_child(eng)
		ship_parts.append(eng)
		var tip := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.05, 0.05, 0.3)
		tip.mesh = tm
		tip.position = Vector3(1.1 * side, -0.05, 0.5)
		tip.material_override = glow_mat
		ship.add_child(tip)
		ship_parts.append(tip)

	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.near = 0.1
	cam.far = 600.0
	cam.current = true
	add_child(cam)
	ship.ui_blocker = _ui_hit  # taps on the VIEW button never start a steering drag

func _build_cockpit() -> void:
	cockpit = HoldCockpit.new()
	cockpit.name = "Cockpit"
	cockpit.visible = false
	add_child(cockpit)

func _build_rocks_assets() -> void:
	rock_mat = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.42, 0.37, 0.33)
	rock_mat.roughness = 0.95
	rock_mat.emission_enabled = true
	rock_mat.emission = Color(0.06, 0.035, 0.02)
	# Readable silhouette: cheap inverted-hull outline glowing warm orange.
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.07
	outline.albedo_color = Color(1.0, 0.45, 0.12)
	outline.disable_fog = false
	rock_mat.next_pass = outline

	var noise := FastNoiseLite.new()
	noise.frequency = 1.6
	for i in ROCK_VARIANTS:
		noise.seed = rng.randi()
		rock_meshes.append(_make_rock_mesh(noise, 0.35 + 0.05 * i))

func _make_rock_mesh(noise: FastNoiseLite, bump: float) -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 9
	sm.rings = 6
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # flat shaded facets = chunky readable rock
	for i in idx:
		var v := verts[i]
		var d := v.normalized()
		# key the noise on rounded position so seam duplicates displace the same way
		var k := (d * 100.0).round() / 100.0
		var r := 1.0 + noise.get_noise_3dv(k * 1.3) * bump * 2.0
		st.add_vertex(d * maxf(r, 0.55))
	st.generate_normals()
	return st.commit()

func _build_streaks() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.035, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_fog = true
	mesh.material = mat
	streaks = MultiMesh.new()
	streaks.transform_format = MultiMesh.TRANSFORM_3D
	streaks.use_colors = true
	streaks.mesh = mesh
	streaks.instance_count = STREAK_COUNT
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = streaks
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 1000.0
	add_child(mmi)
	for i in STREAK_COUNT:
		streak_data.append(_new_streak_pos(rng.randf_range(-VIEW_DIST * 0.8, 5.0)))
		var c := Color(0.55, 0.8, 1.0, 1.0).lerp(Color(1, 1, 1, 1), rng.randf())
		c.a = rng.randf_range(0.35, 0.9)
		streaks.set_instance_color(i, c)

func _new_streak_pos(z: float) -> Vector3:
	var ang := rng.randf() * TAU
	var r := rng.randf_range(2.5, 30.0)
	var base := Vector2.ZERO if ship == null else Vector2(ship.position.x, ship.position.y)
	return Vector3(base.x + cos(ang) * r, base.y + sin(ang) * r, z)

func _update_streaks(delta: float) -> void:
	var len := clampf(speed * 0.09, 4.0, 11.0)
	for i in STREAK_COUNT:
		var p := streak_data[i]
		p.z += speed * delta * 1.15
		if p.z > 6.0:
			p = _new_streak_pos(-VIEW_DIST * rng.randf_range(0.6, 0.8))
		streak_data[i] = p
		var t := Transform3D(Basis.from_scale(Vector3(1, 1, len)), p)
		streaks.set_instance_transform(i, t)

func _build_stars() -> void:
	# Far starfield parented to the camera so it never runs out.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = STAR_COUNT
	for i in STAR_COUNT:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), -1.0).normalized()
		var p := dir * 500.0
		var s := rng.randf_range(0.6, 2.0)
		var b := Basis.looking_at(-dir).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(b, p))
		var c := Color(0.7, 0.8, 1.0).lerp(Color(1.0, 0.9, 0.75), rng.randf())
		mm.set_instance_color(i, c * rng.randf_range(0.5, 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 1000.0
	cam.add_child(mmi)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 0.55, 0.3, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)

	score_label = _label(root, 84, HORIZONTAL_ALIGNMENT_CENTER)
	score_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	score_label.offset_left = -300
	score_label.offset_right = 300
	score_label.offset_top = 48
	score_label.add_theme_color_override("font_color", Color(0.75, 1.0, 1.0))
	combo_label = _label(root, 40, HORIZONTAL_ALIGNMENT_CENTER)
	combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	combo_label.offset_left = -300
	combo_label.offset_right = 300
	combo_label.offset_top = 150
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	combo_label.pivot_offset = Vector2(300, 25)
	best_label = _label(root, 30, HORIZONTAL_ALIGNMENT_CENTER)
	best_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	best_label.offset_left = -300
	best_label.offset_right = 300
	best_label.offset_top = 204
	best_label.modulate = Color(1, 1, 1, 0.75)
	pop_label = _label(root, 64, HORIZONTAL_ALIGNMENT_CENTER)
	pop_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pop_label.offset_left = -300
	pop_label.offset_right = 300
	pop_label.offset_top = -260
	pop_label.offset_bottom = -180
	pop_label.modulate = Color(1, 1, 1, 0)
	dist_label = _label(root, 30, HORIZONTAL_ALIGNMENT_CENTER)
	dist_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dist_label.offset_left = -300
	dist_label.offset_right = 300
	dist_label.offset_top = -160
	dist_label.offset_bottom = -112
	dist_label.modulate = Color(1, 1, 1, 0.8)
	speed_label = _label(root, 30, HORIZONTAL_ALIGNMENT_CENTER)
	speed_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	speed_label.offset_left = -300
	speed_label.offset_right = 300
	speed_label.offset_top = -110
	speed_label.offset_bottom = -60
	speed_label.modulate = Color(0.6, 0.9, 1.0, 0.85)

	crash_label = _label(root, 56, HORIZONTAL_ALIGNMENT_CENTER)
	crash_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crash_label.offset_left = -340
	crash_label.offset_right = 340
	crash_label.offset_top = -160
	crash_label.offset_bottom = -40
	crash_label.modulate = Color(1, 1, 1, 0)
	crash_label.visible = OBSTACLES_ENABLED # no crashes in pure-flying mode

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0.01, 0.04, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var title := _label(overlay, 84, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "HOLD COURSE"
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.offset_left = -360
	title.offset_right = 360
	title.offset_top = -170
	title.offset_bottom = -60
	tap_label = _label(overlay, 56, HORIZONTAL_ALIGNMENT_CENTER)
	tap_label.text = "TAP TO FLY"
	tap_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tap_label.offset_left = -360
	tap_label.offset_right = 360
	tap_label.offset_top = 10
	tap_label.offset_bottom = 90
	tap_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	var how := _label(overlay, 30, HORIZONTAL_ALIGNMENT_CENTER)
	how.text = "Touch & slide anywhere to steer\nFly through the neon rings"
	how.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	how.offset_left = -360
	how.offset_right = 360
	how.offset_top = 100
	how.offset_bottom = 200
	how.modulate = Color(1, 1, 1, 0.75)

	# camera picker on the start screen (tapping it chooses the view, it does not start the flight)
	var cam_title := _label(overlay, 26, HORIZONTAL_ALIGNMENT_CENTER)
	cam_title.text = "CAMERA"
	cam_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cam_title.offset_left = -200
	cam_title.offset_right = 200
	cam_title.offset_top = 215
	cam_title.offset_bottom = 250
	cam_title.modulate = Color(0.7, 0.9, 1.0, 0.8)
	_style_on = _pill_style(true)
	_style_off = _pill_style(false)
	pick_chase = _pill(overlay, "CHASE", -260, -14)
	pick_cockpit = _pill(overlay, "COCKPIT", 14, 260)

	# VIEW button, top-right, always available (start screen and in flight)
	view_btn = Panel.new()
	view_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color(0.02, 0.05, 0.12, 0.55)
	vs.border_color = Color(0.1, 0.95, 1.0, 0.9)
	vs.set_border_width_all(3)
	vs.set_corner_radius_all(24)
	view_btn.add_theme_stylebox_override("panel", vs)
	view_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	view_btn.offset_left = -152
	view_btn.offset_right = -28
	view_btn.offset_top = 36
	view_btn.offset_bottom = 152
	view_btn.pivot_offset = Vector2(62, 58)
	root.add_child(view_btn)
	view_btn_icon = Control.new()
	view_btn_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_btn_icon.position = Vector2(0, 8)
	view_btn_icon.size = Vector2(124, 62)
	view_btn_icon.draw.connect(_draw_view_icon)
	view_btn.add_child(view_btn_icon)
	var vl := _label(view_btn, 28, HORIZONTAL_ALIGNMENT_CENTER)
	vl.text = "VIEW"
	vl.position = Vector2(0, 66)
	vl.size = Vector2(124, 40)
	vl.add_theme_color_override("font_color", Color(0.75, 1.0, 1.0))
	view_mode_label = _label(root, 22, HORIZONTAL_ALIGNMENT_CENTER)
	view_mode_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	view_mode_label.offset_left = -172
	view_mode_label.offset_right = -8
	view_mode_label.offset_top = 156
	view_mode_label.offset_bottom = 186
	view_mode_label.modulate = Color(0.7, 0.95, 1.0, 0.8)

func _pill_style(on: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.75, 0.9, 0.35) if on else Color(0.02, 0.05, 0.12, 0.5)
	st.border_color = Color(0.1, 0.95, 1.0, 1.0) if on else Color(0.5, 0.7, 0.85, 0.5)
	st.set_border_width_all(4 if on else 2)
	st.set_corner_radius_all(40)
	return st

func _pill(parent: Control, text: String, left: float, right: float) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = left
	p.offset_right = right
	p.offset_top = 255
	p.offset_bottom = 345
	parent.add_child(p)
	var l := _label(p, 36, HORIZONTAL_ALIGNMENT_CENTER)
	l.text = text
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return p

func _draw_view_icon() -> void:
	# simple neon eye: almond outline + iris + pupil
	var c := view_btn_icon.size * 0.5 + Vector2(0, 4)
	var col := Color(0.1, 0.95, 1.0)
	var pts := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		pts.append(c + Vector2(lerpf(-34, 34, t), -sin(t * PI) * 19.0))
	for i in range(1, 17):
		var t := 1.0 - float(i) / 16.0
		pts.append(c + Vector2(lerpf(-34, 34, t), sin(t * PI) * 19.0))
	view_btn_icon.draw_polyline(pts, col, 4.0, true)
	view_btn_icon.draw_circle(c, 11.0, col)
	view_btn_icon.draw_circle(c, 5.0, Color(0.02, 0.05, 0.12))

func _label(parent: Control, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build_audio() -> void:
	if OBSTACLES_ENABLED:
		crash_player = AudioStreamPlayer.new()
		crash_player.stream = _make_noise_wav(0.6, true)
		crash_player.volume_db = -4.0
		add_child(crash_player)
	tones = HoldPortalTones.new()   # synthesizes its buffers once, here at startup
	add_child(tones)
	wind_player = AudioStreamPlayer.new()
	wind_player.stream = _make_noise_wav(2.0, false)
	wind_player.volume_db = -24.0   # softer rush so the tones + drone stay in front
	add_child(wind_player)

func _make_noise_wav(seconds: float, burst: bool) -> AudioStreamWAV:
	# Cheap procedural sound: low-passed noise. Burst = decaying crash, else a looped rush.
	var rate := 22050
	var n := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var white := rng.randf_range(-1.0, 1.0)
		var a := 0.08 if not burst else 0.35 * (1.0 - t)
		lp += (white - lp) * a
		lp2 += (lp - lp2) * 0.3
		var env := 1.0
		if burst:
			env = pow(1.0 - t, 2.0)
		else:
			# fade the loop edges so it loops without a click
			env = minf(1.0, minf(t * 20.0, (1.0 - t) * 20.0)) * 0.6 + 0.4
		var s := clampi(int(lp2 * env * 3.2 * 32767.0), -32767, 32767)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if not burst:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w

func _on_resize() -> void:
	var size := get_viewport().get_visible_rect().size
	# Keep ~70 degrees across the SHORT side so portrait and landscape both look right.
	if size.x < size.y:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
	fov_base = 70.0
	# cockpit is laid out in screen terms, so rebuild it for the new aspect
	var t := tan(deg_to_rad(fov_base + COCKPIT_FOV_ADD) * 0.5)
	if size.x < size.y:
		cockpit.layout(t, t * size.y / size.x)
	else:
		cockpit.layout(t * size.x / size.y, t)

# ---------------------------------------------------------------- spawning

func _ramp() -> float:
	return clampf(distance_m / 7000.0, 0.0, 1.0)

func _wave_spacing() -> float:
	return lerpf(34.0, 21.0, _ramp())

func _reset_field(full: bool) -> void:
	# Clear rocks near the ship (all of them if full) and refill ahead with a safe corridor.
	if not OBSTACLES_ENABLED:
		return
	var keep_beyond := -VIEW_DIST - 1.0 if full else -110.0
	for r in rocks.duplicate():
		if r.position.z > keep_beyond:
			rocks.erase(r)
			r.queue_free()
	gap = Vector2(ship.position.x, ship.position.y)
	prev_gap = gap
	var z := -75.0 if full else -110.0
	if not full:
		# respawn from the near edge of the kept rocks
		pass
	var far_limit := -VIEW_DIST if full else -110.0
	if full:
		while z > far_limit:
			_spawn_wave(z)
			z -= _wave_spacing()
	travel_since_wave = 0.0

func _spawn_wave(z: float) -> void:
	if not OBSTACLES_ENABLED:
		return
	var spacing := _wave_spacing()
	var t_between := spacing / speed
	var max_step := 30.0 * t_between * 0.5
	prev_gap = gap
	gap += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.0, max_step)
	gap.x = clampf(gap.x, -11.0, 11.0)
	gap.y = clampf(gap.y, -9.0, 9.0)
	var ramp := _ramp()
	var gap_r := lerpf(5.5, 3.8, ramp)
	var count := int(round(lerpf(4.0, 10.0, ramp))) + rng.randi_range(0, 2)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 6:
		tries += 1
		var scale_f := rng.randf_range(1.2, 3.6)
		if rng.randf() < 0.12:
			scale_f = rng.randf_range(4.0, 6.0) # occasional big boulder
		var dz := rng.randf_range(0.0, 0.4) * spacing # only toward the player, so the corridor check below is exact
		var pos := Vector2(rng.randf_range(-21.0, 21.0), rng.randf_range(-18.0, 18.0))
		# where the safe corridor is at this rock's depth (dz > 0 = closer = toward prev gap)
		var f := clampf(dz / spacing, 0.0, 1.0)
		var corridor := gap.lerp(prev_gap, f)
		var hit_r := scale_f * 0.8
		if pos.distance_to(corridor) < gap_r + hit_r + SHIP_RADIUS:
			continue
		_spawn_rock(Vector3(pos.x, pos.y, z + dz), scale_f)
		placed += 1

func _spawn_rock(p: Vector3, scale_f: float) -> void:
	var rock := HoldRock.new()
	var mi := MeshInstance3D.new()
	mi.mesh = rock_meshes[rng.randi() % rock_meshes.size()]
	mi.material_override = rock_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# slight stretch for distinct silhouettes
	mi.scale = Vector3(rng.randf_range(0.8, 1.25), rng.randf_range(0.75, 1.1), rng.randf_range(0.8, 1.3))
	rock.add_child(mi)
	rock.scale = Vector3.ONE * scale_f
	rock.position = p
	rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
	rock.spin_speed = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8
	rock.radius = scale_f * 0.8
	add_child(rock)
	rocks.append(rock)

# ---------------------------------------------------------------- portals

func _torus(inner: float, outer: float, rings: int, segs: int) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = rings
	t.ring_segments = segs
	return t

func _neon_mat() -> StandardMaterial3D:
	# Unshaded + additive: glows on its own, no bloom / post-processing needed (WebGL safe).
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_fog = true
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _build_portals() -> void:
	# shared low-poly meshes: hot core tube + two soft halo tubes = neon glow without bloom
	var r := PORTAL_RADIUS
	var core := _torus(r - 0.22, r + 0.22, 40, 8)
	var halo1 := _torus(r - 0.6, r + 0.6, 40, 6)
	var halo2 := _torus(r - 1.3, r + 1.3, 32, 6)
	for i in PORTAL_POOL:
		var p := Portal.new()
		p.node = Node3D.new()
		p.node.visible = false
		var spin := Node3D.new()
		spin.rotation_degrees = Vector3(90, 0, 0) # torus axis Y -> facing the ship (Z)
		p.node.add_child(spin)
		for layer in [[core, 1.0], [halo1, 0.42], [halo2, 0.14]]:
			var mi := MeshInstance3D.new()
			mi.mesh = layer[0]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := _neon_mat()
			mi.material_override = m
			spin.add_child(mi)
			p.mats.append(m)
			p.alphas.append(layer[1])
		add_child(p.node)
		portals.append(p)

func _reset_portals() -> void:
	for p in portals:
		p.phase = 0
		p.node.visible = false
	portal_path = Vector2(ship.position.x, ship.position.y) if state == State.FLYING else Vector2.ZERO
	# first ring close-ish and easy, then one ring every PORTAL_SPACING
	last_portal_z = -130.0 + PORTAL_SPACING
	_fill_portals()

func _fill_portals() -> void:
	while last_portal_z - PORTAL_SPACING > -VIEW_DIST - 10.0:
		last_portal_z -= PORTAL_SPACING
		_spawn_portal(last_portal_z)

func _spawn_portal(z: float) -> void:
	var p: Portal = null
	for q in portals:
		if q.phase == 0:
			p = q
			break
	if p == null: # pool exhausted: reuse the ring furthest behind the ship
		p = portals[0]
		for q in portals:
			if q.node.position.z > p.node.position.z:
				p = q
	# readable path: each ring is a reachable step from the previous one
	var step := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.0, PORTAL_MAX_STEP)
	var nxt := portal_path + step
	# bounce back inward instead of hugging the edge
	if absf(nxt.x) > PORTAL_RANGE.x:
		nxt.x = portal_path.x - step.x
	if absf(nxt.y) > PORTAL_RANGE.y:
		nxt.y = portal_path.y - step.y
	nxt.x = clampf(nxt.x, -PORTAL_RANGE.x, PORTAL_RANGE.x)
	nxt.y = clampf(nxt.y, -PORTAL_RANGE.y, PORTAL_RANGE.y)
	portal_path = nxt
	p.color = PORTAL_COLORS[portal_color_i % PORTAL_COLORS.size()]
	portal_color_i += 1
	p.phase = 1
	p.t = 0.0
	p.node.position = Vector3(nxt.x, nxt.y, z)
	p.node.scale = Vector3.ONE
	p.node.visible = true
	_tint_portal(p, 1.0)

func _tint_portal(p: Portal, fade: float) -> void:
	for i in p.mats.size():
		var c: Color = p.color
		if i == 0:
			c = c.lerp(Color.WHITE, 0.45) # whitish hot core like a neon tube
		c.a = p.alphas[i] * fade
		p.mats[i].albedo_color = c

func _next_portal() -> Portal:
	var best: Portal = null
	for p in portals:
		if p.phase == 1 and p.node.position.z < ship.position.z:
			if best == null or p.node.position.z > best.node.position.z:
				best = p
	return best

func _update_portals(delta: float, move: float) -> void:
	last_portal_z += move
	var nxt := _next_portal()
	for p in portals:
		match p.phase:
			1:
				var prev_z := p.node.position.z
				p.node.position.z += move
				p.t += delta
				# the ring you are heading for breathes a little so it reads as "this one"
				var pulse := 1.0 + (0.06 * sin(p.t * 9.0) if p == nxt else 0.0)
				p.node.scale = Vector3.ONE * pulse
				# fade in from the far distance
				var far_fade := clampf((VIEW_DIST + p.node.position.z) / 40.0, 0.0, 1.0)
				_tint_portal(p, far_fade)
				# cockpit: the eye sits at the ship, so don't let the glowing tube sweep across the lens
				p.node.visible = not (view_inside and p.node.position.z > ship.position.z - 1.0)
				if prev_z < ship.position.z and p.node.position.z >= ship.position.z:
					var d := Vector2(p.node.position.x - ship.position.x, p.node.position.y - ship.position.y).length()
					if state == State.FLYING and d <= PORTAL_HIT_RADIUS:
						_portal_hit(p)
					else:
						if state == State.FLYING:
							_portal_miss()
						p.phase = 3
			2:
				# burst: ring stays around the ship, expands and fades out
				p.t += delta
				var k := clampf(p.t / 0.4, 0.0, 1.0)
				p.node.scale = Vector3.ONE * lerpf(1.0, 2.4, 1.0 - pow(1.0 - k, 3.0))
				# chase: around the ship; cockpit: a few metres ahead of the eye so it reads as a ring you burst through
				p.node.position.z = ship.position.z - 0.5 - 5.0 * _ease_view(view_blend)
				p.node.visible = true
				_tint_portal(p, 1.0 - k)
				if k >= 1.0:
					p.phase = 0
					p.node.visible = false
			3:
				p.node.position.z += move
				_tint_portal(p, 0.35)
				p.node.visible = not (view_inside and p.node.position.z > ship.position.z - 1.0)
				if p.node.position.z > 12.0:
					p.phase = 0
					p.node.visible = false
	_fill_portals()

func _portal_hit(p: Portal) -> void:
	combo += 1
	portals_hit += 1
	var mult := mini(combo, COMBO_MAX)
	var pts := PORTAL_POINTS * mult
	score += pts
	p.phase = 2
	p.t = 0.0
	pop_label.text = "+%d" % pts
	pop_label.add_theme_color_override("font_color", p.color.lerp(Color.WHITE, 0.3))
	pop_t = 0.7
	combo_bump = 1.0
	flash_rect.color = Color(p.color.r, p.color.g, p.color.b, 0.22)
	fov_kick = maxf(fov_kick, 5.0)
	shake = maxf(shake, 0.05)
	tones.play_portal(mult)

func _portal_miss() -> void:
	portals_missed += 1
	if combo > 1:
		pop_label.text = "COMBO LOST"
		pop_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		pop_t = 0.6
	combo = 0

# ---------------------------------------------------------------- loop

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if k == KEY_C or k == KEY_V:
			_toggle_view()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenTouch and event.pressed:
		# UI taps are consumed: they never start the flight or a steering drag (ship.gd checks _ui_hit too)
		match _ui_target(event.position):
			"view":
				_toggle_view()
				get_viewport().set_input_as_handled()
				return
			"chase":
				_set_view(false)
				get_viewport().set_input_as_handled()
				return
			"cockpit":
				_set_view(true)
				get_viewport().set_input_as_handled()
				return
		if state == State.ATTRACT:
			_start_flight()

func _ui_target(pos: Vector2) -> String:
	if view_btn != null and view_btn.visible and view_btn.get_global_rect().grow(14.0).has_point(pos):
		return "view"
	if state == State.ATTRACT and overlay.visible:
		if pick_chase.get_global_rect().grow(6.0).has_point(pos):
			return "chase"
		if pick_cockpit.get_global_rect().grow(6.0).has_point(pos):
			return "cockpit"
	return ""

func _ui_hit(pos: Vector2) -> bool:
	return _ui_target(pos) != ""

func _toggle_view() -> void:
	_set_view(not view_cockpit)

func _set_view(cockpit_on: bool) -> void:
	view_btn_bump = 1.0
	if cockpit_on == view_cockpit:
		return
	view_cockpit = cockpit_on
	_apply_view_ui()
	_save_best() # remember the choice for next launch

func _apply_view_ui() -> void:
	if view_mode_label != null:
		view_mode_label.text = "COCKPIT" if view_cockpit else "CHASE"
	if pick_chase != null:
		pick_chase.add_theme_stylebox_override("panel", _style_off if view_cockpit else _style_on)
		pick_cockpit.add_theme_stylebox_override("panel", _style_on if view_cockpit else _style_off)

func _start_flight() -> void:
	state = State.FLYING
	ship.enabled = true
	overlay.visible = false
	distance_m = 0.0
	speed = BASE_SPEED
	score = 0
	combo = 0
	portals_hit = 0
	portals_missed = 0
	_reset_field(true)
	_reset_portals()
	fov_kick = 14.0
	shake = 0.25
	if not wind_player.playing:
		wind_player.play()
	tones.reset()        # melody starts from the top each flight
	tones.start_drone()  # very quiet D drone bed, fades in over 3 s

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if state == State.FLYING:
		speed = lerpf(BASE_SPEED, MAX_SPEED, _ramp())
		distance_m += speed * delta
	else:
		overlay_t += delta
		tap_label.modulate.a = 0.55 + 0.45 * sin(overlay_t * 4.0)
		# attract mode: gentle auto-weave so the start screen already feels like flight
		ship.position.x = sin(overlay_t * 0.7) * 3.0
		ship.position.y = sin(overlay_t * 0.5) * 1.5
		ship.rotation.z = -cos(overlay_t * 0.7) * 0.25

	var move := speed * delta
	if OBSTACLES_ENABLED:
		_update_obstacles(delta, move)
	if state == State.FLYING and (distance_m > best_m or score > best_score):
		# no crashes any more, so bests are saved while flying (throttled)
		best_m = maxf(best_m, distance_m)
		best_score = maxi(best_score, score)
		_best_save_t += delta
		if _best_save_t > 3.0:
			_best_save_t = 0.0
			_save_best()
	_update_portals(delta, move)

	_update_streaks(delta)

	_update_camera(delta)
	_update_hud(delta)
	_web_publish(delta)

func _update_obstacles(_delta: float, move: float) -> void:
	# Rock movement, swept collision, wave spawning and crash. Only runs when OBSTACLES_ENABLED.
	var hit := false
	for r in rocks.duplicate():
		var prev_z: float = r.position.z
		r.position.z += move
		if r.position.z > 15.0:
			rocks.erase(r)
			r.queue_free()
			continue
		if state == State.FLYING and not hit:
			# swept test so nothing tunnels through at speed
			var cz := clampf(ship.position.z, prev_z, r.position.z)
			var d := Vector3(r.position.x - ship.position.x, r.position.y - ship.position.y, cz - ship.position.z)
			if d.length() < r.radius + SHIP_RADIUS:
				hit = true

	travel_since_wave += move
	var spacing := _wave_spacing()
	while travel_since_wave >= spacing:
		travel_since_wave -= spacing
		_spawn_wave(-VIEW_DIST)

	if hit:
		_crash()

func _ease_view(t: float) -> float:
	# cubic ease-in-out
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0

func _update_camera(delta: float) -> void:
	fov_kick = move_toward(fov_kick, 0.0, delta * 18.0)
	var steer_fov := Vector2(ship.velocity.x, ship.velocity.y).length() / 34.0 * 3.0 if state == State.FLYING else 0.0
	var chase_fov := fov_base + fov_kick + steer_fov + (speed - BASE_SPEED) * 0.15
	shake = move_toward(shake, 0.0, delta * 1.5)
	view_blend = move_toward(view_blend, 1.0 if view_cockpit else 0.0, delta / VIEW_TRANSITION)
	var e := _ease_view(view_blend)
	var s := (0.015 + shake) * lerpf(1.0, COCKPIT_SHAKE, e)
	var jitter := Vector3(rng.randf_range(-s, s), rng.randf_range(-s, s), 0)
	# CHASE pose (unchanged): behind + above, slight bank + pitch with the ship for feel
	var chase_pos := ship.position + CHASE_OFFSET + jitter
	var chase_basis := Basis.from_euler(Vector3(-0.02 + ship.rotation.x * 0.3, -ship.velocity.x / ship.max_lateral_speed * 0.03, ship.rotation.z * 0.45))
	if e <= 0.0:
		cam.position = chase_pos
		cam.basis = chase_basis
		cam.fov = chase_fov
	# COCKPIT pose: pilot's eye, rolls + pitches with the ship (a little softer than the hull)
	var head_basis := Basis.from_euler(Vector3(ship.rotation.x * 0.8, -ship.velocity.x / ship.max_lateral_speed * 0.04, ship.rotation.z * 0.8))
	var head_pos := ship.position + ship.basis.orthonormalized() * (HEAD_OFFSET * ship.scale.x) + jitter
	cockpit.transform = Transform3D(head_basis, head_pos)
	var cockpit_fov := fov_base + COCKPIT_FOV_ADD + fov_kick * 0.8 + steer_fov + (speed - BASE_SPEED) * 0.15
	if e > 0.0:
		# fly the camera between the two poses: position + rotation (slerp) + FOV
		var q := chase_basis.get_rotation_quaternion().slerp(head_basis.get_rotation_quaternion(), e)
		cam.basis = Basis(q)
		cam.position = chase_pos.lerp(head_pos, e)
		cam.fov = lerpf(chase_fov, cockpit_fov, e)
	# swap hull <-> cockpit when the camera is right at the canopy, so it reads as flying in
	var inside := e >= VIEW_SWAP_AT
	if inside != view_inside:
		view_inside = inside
		for part in ship_parts:
			part.visible = not inside
		cockpit.visible = inside
		flash_rect.color = Color(0.0, 0.03, 0.08, 0.35) # brief canopy "blink" hides the swap
	if cockpit.visible:
		var np := _next_portal()
		var rel := np.node.position - ship.position if np != null else Vector3.ZERO
		cockpit.tick(delta, mini(combo, COMBO_MAX) if state == State.FLYING else 0, np != null, rel)

func _update_hud(delta: float) -> void:
	if state == State.FLYING:
		score_label.text = str(score)
		combo_label.text = "x%d COMBO" % mini(combo, COMBO_MAX) if combo >= 2 else ""
		best_label.text = "BEST %d" % maxi(best_score, score)
		dist_label.text = "%d m" % int(distance_m)
		speed_label.text = "%d km/h" % int(speed * 3.6)
	else:
		score_label.text = ""
		combo_label.text = ""
		best_label.text = ("BEST %d" % best_score) if best_score > 0 else ""
		dist_label.text = ""
		speed_label.text = "%d km/h" % int(speed * 3.6)
	view_btn_bump = move_toward(view_btn_bump, 0.0, delta * 5.0)
	view_btn.scale = Vector2.ONE * (1.0 - 0.1 * view_btn_bump)
	combo_bump = move_toward(combo_bump, 0.0, delta * 4.0)
	combo_label.scale = Vector2.ONE * (1.0 + 0.25 * combo_bump)
	pop_t = maxf(pop_t - delta, 0.0)
	pop_label.modulate.a = clampf(pop_t / 0.3, 0.0, 1.0)
	pop_label.offset_top = -260 - (0.7 - pop_t) * 60.0
	pop_label.offset_bottom = pop_label.offset_top + 80
	flash_rect.color.a = move_toward(flash_rect.color.a, 0.0, delta * 2.5)
	crash_label_t = maxf(crash_label_t - delta, 0.0)
	crash_label.modulate.a = clampf(crash_label_t / 0.4, 0.0, 1.0)

func _crash() -> void:
	crashes += 1
	var new_best := distance_m > best_m
	if new_best:
		best_m = distance_m
		_save_best()
	crash_label.text = ("NEW BEST  %d m" if new_best else "CRASH  %d m") % int(distance_m)
	crash_label_t = 1.4
	flash_rect.color = Color(1.0, 0.55, 0.3, 0.85) if not new_best else Color(0.5, 0.9, 1.0, 0.85)
	shake = 0.6
	fov_kick = 16.0
	crash_player.play()
	# instant restart: no menu, straight back into the rush
	distance_m = 0.0
	speed = BASE_SPEED
	ship.velocity = Vector3.ZERO
	_reset_field(true)

# ---------------------------------------------------------------- save

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if best_m > 0.0 or best_score > 0:
			_save_best()

func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_m = float(cfg.get_value("run", "best_m", 0.0))
		best_score = int(cfg.get_value("run", "best_score", 0))
		view_cockpit = str(cfg.get_value("settings", "view", "chase")) == "cockpit"
		view_blend = 1.0 if view_cockpit else 0.0

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "best_m", best_m)
	cfg.set_value("run", "best_score", best_score)
	cfg.set_value("settings", "view", "cockpit" if view_cockpit else "chase")
	cfg.save(SAVE_PATH) # on web, user:// is IndexedDB and syncs on close

# ---------------------------------------------------------------- web glue

func _web_setup() -> void:
	if not OS.has_feature("web"):
		return
	# Ask for fullscreen on the first tap on touch devices (browsers only allow it inside a gesture).
	# iPhone Safari has no element fullscreen; the guard just skips it there.
	JavaScriptBridge.eval("""
	(function(){
	  var c = document.getElementById('canvas') || document.querySelector('canvas');
	  if (!c) return;
	  var go = function(){
	    try {
	      if (!window.matchMedia || !window.matchMedia('(pointer: coarse)').matches) return;
	      var el = document.documentElement;
	      var rf = el.requestFullscreen || el.webkitRequestFullscreen;
	      if (rf && !document.fullscreenElement) { var p = rf.call(el); if (p && p.catch) p.catch(function(){}); }
	    } catch(e) {}
	  };
	  c.addEventListener('touchend', go, {once:true});
		})();
	""", true)

func _web_publish(delta: float) -> void:
	# Small status object for automated browser tests: window.holdCourse
	if not OS.has_feature("web"):
		return
	_js_t += delta
	if _js_t < 0.1:
		return
	_js_t = 0.0
	var np := _next_portal()
	var npos := np.node.position if np != null else Vector3(0, 0, 0)
	JavaScriptBridge.eval(("window.holdCourse={state:'%s',distance:%d,best:%d,x:%.2f,y:%.2f,vx:%.2f,vy:%.2f,holding:%s,obstacles:%s,crashes:%d,rocks:%d,"
		+ "score:%d,bestScore:%d,combo:%d,portalsHit:%d,portalsMissed:%d,nextPortal:%s,nextX:%.2f,nextY:%.2f,nextZ:%.1f,sensitivity:%.2f,"
		+ "soundSeq:%d,lastNote:%d,lastVoice:%d,noteHist:%s,voiceHist:%s,"
		+ "view:'%s',viewBlend:%.3f,viewTransition:%s,viewInside:%s,viewBtn:%s,pickChase:%s,pickCockpit:%s};") % [
		"flying" if state == State.FLYING else "attract", int(distance_m), int(best_m),
		ship.position.x, ship.position.y, ship.velocity.x, ship.velocity.y, "true" if ship.holding else "false",
		"true" if OBSTACLES_ENABLED else "false", crashes, rocks.size(),
		score, best_score, combo, portals_hit, portals_missed, "true" if np != null else "false",
		npos.x, npos.y, npos.z, HoldShip.STEER_SENSITIVITY,
		tones.step, tones.last_note, tones.last_voice, JSON.stringify(tones.note_hist), JSON.stringify(tones.voice_hist),
		"cockpit" if view_cockpit else "chase", view_blend,
		"true" if view_blend != (1.0 if view_cockpit else 0.0) else "false", "true" if view_inside else "false",
		_frac_rect(view_btn), _frac_rect(pick_chase), _frac_rect(pick_cockpit)], true)

func _frac_rect(c: Control) -> String:
	# centre of a UI control as a fraction of the screen (for the browser test), [] when hidden
	if c == null or not c.is_visible_in_tree():
		return "[]"
	var vs := get_viewport().get_visible_rect().size
	var r := c.get_global_rect()
	return "[%.4f,%.4f]" % [r.get_center().x / vs.x, r.get_center().y / vs.y]
