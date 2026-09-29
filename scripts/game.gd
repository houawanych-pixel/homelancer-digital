extends Node3D

var ship: Node3D
var camera: Camera3D
var world: Node3D
var beacon: Node3D
var station: Node3D
var enemy: Node3D
var hud: Label
var system := 0
var credits := 0
var hull := 100
var shield := 100.0
var repairs := 5
var missiles := 4
var weapon := 1
var enemy_hull := 8
var docked := false
var charge := 0.0
var cooldown := 0.0
var missile_cooldown := 0.0
var auto_fire := true
var move_touch := Vector2.ZERO
var aim_touch := Vector2.ZERO
var message := "Destroy the drone, dock, then warp."
var left_origin := Vector2.ZERO
var right_origin := Vector2.ZERO
var left_id := -1
var right_id := -1
var btn_auto := Rect2()
var btn_missile := Rect2()
var btn_repair := Rect2()

func _ready() -> void:
	var keys := {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"fire":KEY_SPACE,"dock":KEY_F,"launch":KEY_R,"upgrade":KEY_U,"warp":KEY_T,"boost":KEY_SHIFT,"missile":KEY_Q,"repair":KEY_E,"auto":KEY_TAB}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action,event)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.005,0.01,0.035)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5,0.55,0.7)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30,-40,0)
	add_child(sun)
	ship = shape("Player",false,2.0,Color.CYAN)
	add_child(ship)
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(20,16)
	hud.add_theme_font_size_override("font_size",20)
	canvas.add_child(hud)
	load_system(0)
	queue_redraw()

func shape(title:String,sphere:bool,size:float,tint:Color)->Node3D:
	var node:=Node3D.new(); node.name=title
	var mi:=MeshInstance3D.new()
	mi.mesh = SphereMesh.new() if sphere else BoxMesh.new()
	mi.scale=Vector3.ONE*size
	var mat:=StandardMaterial3D.new(); mat.albedo_color=tint
	mi.material_override=mat; node.add_child(mi)
	return node

func load_system(next:int)->void:
	if is_instance_valid(world): world.queue_free()
	world=Node3D.new(); add_child(world); system=next
	ship.position=Vector3.ZERO; ship.rotation=Vector3.ZERO; charge=0; docked=false
	var palette=[Color.RED,Color.GREEN] if next==0 else [Color.BLUE,Color.YELLOW]
	for i in 2:
		var p:=shape("Planet %d"%i,true,6.0 if i==0 else 4.0,palette[i])
		p.position=Vector3(-65.0+i*130.0,8,-110-i*40); world.add_child(p)
	for i in 14:
		var r:=shape("Asteroid %d"%i,true,0.8+float(i%4)*0.35,Color(0.45,0.4,0.36))
		r.position=Vector3(sin(float(i)*11.3)*43,cos(float(i)*5.2)*12,-15-i*7); world.add_child(r)
	beacon=shape("Warp beacon",true,3,Color(0.1,0.7,1)); beacon.position=Vector3(0,0,-95); world.add_child(beacon)
	station=null; enemy=null
	if next==0:
		station=shape("Hub station",false,9,Color(0.75,0.75,0.8)); station.position=Vector3(-25,0,-35); world.add_child(station)
		enemy=shape("Enemy drone",false,2,Color(1,0.25,0.12)); enemy.position=Vector3(17,0,-50); world.add_child(enemy); enemy_hull=8
	message="System %s ready."%("A" if next==0 else "B")

func _process(delta:float)->void:
	cooldown=maxf(0,cooldown-delta); missile_cooldown=maxf(0,missile_cooldown-delta)
	shield=minf(100.0,shield+7.0*delta)
	if Input.is_action_just_pressed("auto"): auto_fire=!auto_fire
	if Input.is_action_just_pressed("repair"): use_repair()
	if Input.is_action_just_pressed("missile"): fire_missile()
	if not docked:
		var turn=Input.get_action_strength("left")-Input.get_action_strength("right")-aim_touch.x
		ship.rotate_y(turn*delta*1.8)
		var thrust=Input.get_action_strength("forward")-Input.get_action_strength("back")*0.5-move_touch.y
		var strafe=move_touch.x
		var speed=70.0 if Input.is_action_pressed("boost") else 32.0
		ship.position-=ship.global_basis.z*thrust*speed*delta
		ship.position+=ship.global_basis.x*strafe*speed*0.7*delta
		var target_locked=is_instance_valid(enemy) and ship.position.distance_to(enemy.position)<80 and (-ship.global_basis.z).dot((enemy.position-ship.position).normalized())>0.92
		if (Input.is_action_pressed("fire") or (auto_fire and target_locked)) and cooldown<=0: shoot()
		if is_instance_valid(station) and ship.position.distance_to(station.position)<16 and Input.is_action_just_pressed("dock"):
			docked=true; hull=100; shield=100; repairs=5; missiles=4; message="Docked: repaired and resupplied."
		if ship.position.distance_to(beacon.position)<19 and Input.is_action_pressed("warp"):
			charge+=delta
			if charge>1.5: load_system(1-system)
		else: charge=0
	else:
		if Input.is_action_just_pressed("upgrade") and credits>=10: credits-=10; weapon+=1; message="Weapon upgraded."
		if Input.is_action_just_pressed("launch"): docked=false; message="Launched."
	var behind=ship.position+ship.global_basis.z*14+Vector3(0,6,0)
	camera.position=camera.position.lerp(behind,minf(1,delta*5)); camera.look_at(ship.position-ship.global_basis.z*15,Vector3.UP)
	hud.text="HOMELANCER DIGITAL — BUILD 01\nSYSTEM %s   HULL %d   SHIELD %d%%   REPAIRS %d   MISSILES %d\nCREDITS %d   WEAPON %d   FIRE %s\n%s"%["A" if system==0 else "B",hull,int(shield),repairs,missiles,credits,weapon,"AUTO" if auto_fire else "MANUAL",message]
	queue_redraw()

func shoot()->void:
	cooldown=0.22
	if not is_instance_valid(enemy): return
	var d=enemy.position-ship.position
	if d.length()<80 and (-ship.global_basis.z).dot(d.normalized())>0.92:
		enemy_hull-=weapon; message="Laser hit — drone hull %d"%maxi(0,enemy_hull)
		if enemy_hull<=0: enemy.queue_free(); credits+=10; message="Drone destroyed +10 credits."

func fire_missile()->void:
	if missiles<=0 or missile_cooldown>0 or not is_instance_valid(enemy): return
	var d=enemy.position-ship.position
	if d.length()<120:
		missiles-=1; missile_cooldown=1.0; enemy_hull-=4; message="Missile impact."
		if enemy_hull<=0: enemy.queue_free(); credits+=10; message="Drone destroyed +10 credits."

func use_repair()->void:
	if repairs>0 and hull<100: repairs-=1; hull=mini(100,hull+35); message="Repair used."

func _input(event:InputEvent)->void:
	var size=get_viewport().get_visible_rect().size
	btn_auto=Rect2(size.x-190,20,170,55); btn_missile=Rect2(size.x-190,size.y-160,170,55); btn_repair=Rect2(size.x-190,size.y-95,170,55)
	if event is InputEventScreenTouch:
		if event.pressed:
			if btn_auto.has_point(event.position): auto_fire=!auto_fire; return
			if btn_missile.has_point(event.position): fire_missile(); return
			if btn_repair.has_point(event.position): use_repair(); return
			if event.position.x<size.x*0.5 and left_id<0: left_id=event.index; left_origin=event.position
			elif right_id<0: right_id=event.index; right_origin=event.position
		else:
			if event.index==left_id: left_id=-1; move_touch=Vector2.ZERO
			if event.index==right_id: right_id=-1; aim_touch=Vector2.ZERO
	elif event is InputEventScreenDrag:
		if event.index==left_id: move_touch=((event.position-left_origin)/90.0).limit_length(1)
		if event.index==right_id: aim_touch=((event.position-right_origin)/90.0).limit_length(1)

func _draw()->void:
	var size=get_viewport().get_visible_rect().size
	draw_circle(Vector2(115,size.y-115),72,Color(0.1,0.5,0.8,0.25)); draw_circle(Vector2(size.x-115,size.y-260),72,Color(0.8,0.5,0.1,0.22))
	draw_rect(Rect2(size.x-190,20,170,55),Color(0.1,0.5,0.8,0.45)); draw_string(ThemeDB.fallback_font,Vector2(size.x-170,55),"AUTO / MANUAL",HORIZONTAL_ALIGNMENT_LEFT,145,18)
	draw_rect(Rect2(size.x-190,size.y-160,170,55),Color(0.7,0.3,0.1,0.5)); draw_string(ThemeDB.fallback_font,Vector2(size.x-165,size.y-125),"MISSILE",HORIZONTAL_ALIGNMENT_LEFT,130,20)
	draw_rect(Rect2(size.x-190,size.y-95,170,55),Color(0.1,0.6,0.3,0.5)); draw_string(ThemeDB.fallback_font,Vector2(size.x-165,size.y-60),"REPAIR",HORIZONTAL_ALIGNMENT_LEFT,130,20)
