extends Node3D
class_name HoldCockpit
## 2026-11-01 (Daniel): first-person cockpit interior for the COCKPIT camera view.
## Low-poly, built in code, laid out in SCREEN terms (NDC: -1..1 across the screen) so the
## canopy frame hugs the screen edges in portrait and landscape and never covers the centre,
## where the portals are. Local space: the pilot's eye is at the origin looking down -Z.
## main.gd puts this node on the pilot's head pose every frame and, in cockpit view, puts the
## camera exactly here, so the cockpit stays steady in view and rolls with the ship.

const CYAN := Color(0.1, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.2, 0.85)
const YELLOW := Color(1.0, 0.9, 0.15)
const GREEN := Color(0.35, 1.0, 0.45)
const COMBO_SEGS := 8
const LIP_D := 0.8          ## depth of the dashboard's top edge
const LIP_NY := -0.64       ## dashboard top edge height on screen (centre part)

var tx := 0.7   ## tan(half horizontal fov) the layout was built for
var ty := 1.5   ## tan(half vertical fov)
var geo: Node3D
var hull_mat: StandardMaterial3D
var hull_dark_mat: StandardMaterial3D
var screen_mat: StandardMaterial3D
var combo_mats: Array[StandardMaterial3D] = []
var blink_mats: Array[StandardMaterial3D] = []
var blink_cols: Array[Color] = []
var blip: MeshInstance3D
var blip_mat: StandardMaterial3D
var radar_c := Vector3.ZERO
var radar_r := 0.1
var _R := Vector3.RIGHT
var _U := Vector3.UP
var _N := Vector3.BACK
var _face_p := Vector3.ZERO
var _t := 0.0

func _init() -> void:
	hull_mat = _lit(Color(0.2, 0.23, 0.32), 0.5, 0.45)
	hull_dark_mat = _lit(Color(0.07, 0.08, 0.12), 0.3, 0.6)
	screen_mat = _neon(Color(0.0, 0.03, 0.07), 1.0, false)

# ------------------------------------------------------------------ materials
func _lit(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	return m

func _neon(c: Color, a: float, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	c.a = a
	m.albedo_color = c
	if additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

# ------------------------------------------------------------------ helpers
func P(nx: float, ny: float, d: float) -> Vector3:
	return Vector3(nx * d * tx, ny * d * ty, -d)

func _mesh(mat: Material, tris: PackedVector3Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n := (b - a).cross(c - a).normalized()
		if n.dot(-(a + b + c) / 3.0) < 0.0:
			n = -n # face the pilot
		for v in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	geo.add_child(mi)
	return mi

func _quad(arr: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	arr.append_array([a, b, c, a, c, d])

func _beam(a: Vector3, b: Vector3, w: float, h: float, mat: Material) -> MeshInstance3D:
	## box from a to b; its "h" side faces the pilot
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) * 0.5
	var up_hint := -mid.normalized()
	var fwd := (b - a).normalized()
	if absf(fwd.dot(up_hint)) > 0.98:
		up_hint = Vector3.UP
	mi.transform = Transform3D(Basis.looking_at(fwd, up_hint), mid)
	geo.add_child(mi)
	return mi

func _face_at(nx: float, ny: float) -> Vector3:
	## where the eye ray through screen point (nx, ny) hits the dashboard face
	var dir := Vector3(nx * tx, ny * ty, -1.0)
	var t := _face_p.dot(_N) / dir.dot(_N)
	return dir * t + _N * 0.004

func _disc(c: Vector3, r0: float, r1: float, segs: int, mat: Material) -> MeshInstance3D:
	var tris := PackedVector3Array()
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var o0 := c + (_R * cos(a0) + _U * sin(a0)) * r1
		var o1 := c + (_R * cos(a1) + _U * sin(a1)) * r1
		if r0 <= 0.0:
			tris.append_array([c, o0, o1])
		else:
			var i0 := c + (_R * cos(a0) + _U * sin(a0)) * r0
			var i1 := c + (_R * cos(a1) + _U * sin(a1)) * r0
			_quad(tris, i0, o0, o1, i1)
	return _mesh(mat, tris)

func _rect(c: Vector3, w: float, h: float, mat: Material) -> MeshInstance3D:
	var tris := PackedVector3Array()
	var rx := _R * w * 0.5
	var uy := _U * h * 0.5
	_quad(tris, c - rx - uy, c + rx - uy, c + rx + uy, c - rx + uy)
	return _mesh(mat, tris)

# ------------------------------------------------------------------ build
func layout(tan_x: float, tan_y: float) -> void:
	tx = tan_x
	ty = tan_y
	if geo != null:
		geo.free()
	combo_mats.clear()
	blink_mats.clear()
	blink_cols.clear()
	geo = Node3D.new()
	add_child(geo)
	_build_dash()
	_build_frame()
	_build_instruments()
	_build_reticle()

func _build_dash() -> void:
	# top edge of the dashboard: flat in the middle, dipping toward the sides
	var lip_n := [Vector2(-2.0, LIP_NY - 0.2), Vector2(-0.85, LIP_NY), Vector2(0.85, LIP_NY), Vector2(2.0, LIP_NY - 0.2)]
	var lip: Array[Vector3] = []
	var far: Array[Vector3] = []
	var bot: Array[Vector3] = []
	for n in lip_n:
		var p := P(n.x, n.y, LIP_D)
		lip.append(p)
		far.append(p + Vector3(0, -0.012 * ty, -0.16))      # glare-shield top, sloping away
		bot.append(Vector3(p.x * 0.8, -1.1 * ty, -0.42))     # face leans back toward the pilot, off-screen
	var face := PackedVector3Array()
	var top := PackedVector3Array()
	for i in lip.size() - 1:
		_quad(face, lip[i], lip[i + 1], bot[i + 1], bot[i])
		_quad(top, far[i], far[i + 1], lip[i + 1], lip[i])
	_mesh(hull_dark_mat, face)
	_mesh(hull_mat, top)
	# neon trim on the glare-shield edge (the silhouette against space) + a fainter one on the lip
	for i in far.size() - 1:
		_beam(far[i] + Vector3(0, 0.004, 0), far[i + 1] + Vector3(0, 0.004, 0), 0.006, 0.006, _neon(CYAN, 0.9))
		_beam(lip[i], lip[i + 1], 0.004, 0.004, _neon(MAGENTA, 0.45))
	# plane of the centre dashboard face, for the instruments
	_face_p = lip[1]
	_R = Vector3.RIGHT
	_U = (lip[1] - bot[1]).normalized()
	_N = _R.cross(_U).normalized()
	if _N.dot(-_face_p) < 0.0:
		_N = -_N

func _build_frame() -> void:
	# canopy frame: two side pillars + an arched bow across the top, all hugging the edges
	var d := 0.62
	var k := d * minf(tx, ty)
	var w := 0.075 * k
	var arch := [Vector2(-1.04, 0.9), Vector2(-0.55, 1.0), Vector2(0.0, 1.04), Vector2(0.55, 1.0), Vector2(1.04, 0.9)]
	var pts: Array[Vector3] = []
	for a in arch:
		pts.append(P(a.x, a.y, d))
	for side in [-1.0, 1.0]:
		var base := P(0.9 * side, LIP_NY - 0.02, LIP_D - 0.02)
		var top: Vector3 = pts[0] if side < 0 else pts[pts.size() - 1]
		_beam(base, top, w * 1.25, w, hull_mat)
		# neon strip on the inner edge of the pillar
		var inward := Vector3(-side, 0, 0) * w * 0.7
		_beam(base + inward + Vector3(0, 0, 0.01), top + inward + Vector3(0, 0, 0.01), 0.0045, 0.0045, _neon(CYAN, 0.75))
	for i in pts.size() - 1:
		_beam(pts[i], pts[i + 1], w, w * 0.8, hull_mat)
		var down := Vector3(0, -w * 0.65, 0.01)
		_beam(pts[i] + down, pts[i + 1] + down, 0.004, 0.004, _neon(MAGENTA, 0.6))

func _build_instruments() -> void:
	var cyan_line := _neon(CYAN, 0.85)
	# --- left: radar with a blip for the next portal
	radar_c = _face_at(-0.6, LIP_NY - 0.17)
	var k := -radar_c.z * minf(tx, ty)
	radar_r = 0.15 * k
	_disc(radar_c, 0.0, radar_r * 1.12, 24, hull_mat)
	_disc(radar_c + _N * 0.001, 0.0, radar_r, 24, screen_mat)
	_disc(radar_c + _N * 0.002, radar_r * 0.93, radar_r, 32, cyan_line)
	_disc(radar_c + _N * 0.002, radar_r * 0.47, radar_r * 0.5, 24, _neon(CYAN, 0.35))
	_rect(radar_c + _N * 0.002, radar_r * 1.86, radar_r * 0.03, _neon(CYAN, 0.25))
	_rect(radar_c + _N * 0.002, radar_r * 0.03, radar_r * 1.86, _neon(CYAN, 0.25))
	blip_mat = _neon(MAGENTA, 1.0)
	blip = _disc(Vector3.ZERO, 0.0, radar_r * 0.12, 10, blip_mat)
	# --- right: combo meter (8 segments light up with the combo)
	var cm := _face_at(0.6, LIP_NY - 0.17)
	var kc := -cm.z * minf(tx, ty)
	var panel_w := 0.36 * kc
	_rect(cm, panel_w * 1.08, 0.2 * kc, hull_mat)
	_rect(cm + _N * 0.001, panel_w, 0.16 * kc, screen_mat)
	var seg_w := panel_w / COMBO_SEGS
	for i in COMBO_SEGS:
		var f := float(i) / (COMBO_SEGS - 1)
		var col := GREEN.lerp(YELLOW, clampf(f * 2.0, 0, 1)).lerp(MAGENTA, clampf(f * 2.0 - 1.0, 0, 1))
		var m := _neon(col, 0.15)
		combo_mats.append(m)
		var h := (0.05 + 0.08 * f) * kc
		var c := cm + _R * (-panel_w * 0.5 + seg_w * (i + 0.5)) + _U * (h * 0.5 - 0.06 * kc) + _N * 0.002
		_rect(c, seg_w * 0.68, h, m)
	# --- centre: a row of small indicator lights just under the dashboard edge
	var cols := [CYAN, GREEN, YELLOW, MAGENTA, CYAN]
	for i in cols.size():
		var p := _face_at(-0.2 + 0.1 * i, LIP_NY - 0.07)
		var kp := -p.z * minf(tx, ty)
		var m := _neon(cols[i], 0.9)
		blink_mats.append(m)
		blink_cols.append(cols[i])
		_disc(p, 0.0, 0.013 * kp, 10, m)
		_disc(p - _N * 0.001, 0.0, 0.03 * kp, 12, _neon(cols[i], 0.18))

func _build_reticle() -> void:
	# faint HUD ring projected on the canopy: shows the ship's centre without hiding portals
	var d := 4.0
	var k := d * minf(tx, ty)
	var save := [_R, _U]
	_R = Vector3.RIGHT
	_U = Vector3.UP
	var c := Vector3(0, 0, -d)
	var m := _neon(CYAN, 0.5)
	_disc(c, 0.068 * k, 0.074 * k, 40, m)
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector3(cos(a), sin(a), 0)
		_beam(c + dir * 0.085 * k, c + dir * 0.115 * k, 0.006 * k, 0.006 * k, m)
	_R = save[0]
	_U = save[1]

# ------------------------------------------------------------------ live
func tick(delta: float, combo: int, has_next: bool, rel: Vector3) -> void:
	_t += delta
	for i in combo_mats.size():
		combo_mats[i].albedo_color.a = 1.0 if i < combo else 0.13
	for i in blink_mats.size():
		var a := 0.55 + 0.45 * sin(_t * (1.3 + 0.37 * i) + i * 1.7)
		blink_mats[i].albedo_color.a = a
	if blip != null:
		blip.visible = has_next
		if has_next:
			var v := Vector2(rel.x, rel.y) / 16.0
			v = v.limit_length(1.0)
			blip.position = radar_c + (_R * v.x + _U * v.y) * radar_r * 0.85 + _N * 0.003
			var near := clampf(1.0 + rel.z / 240.0, 0.0, 1.0)
			blip.scale = Vector3.ONE * lerpf(0.6, 1.5, near)
			blip_mat.albedo_color.a = 0.5 + 0.5 * near
