extends Node3D

var ship:Node3D; var camera:Camera3D; var world:Node3D; var hud:Label
var station:Node3D; var planet:Node3D; var gate:Node3D; var enemy:Node3D
var system:=0; var credits:=250; var hull:=100; var shield:=100.0; var repairs:=5; var missiles:=4
var weapon:=1; var ship_class:=0; var enemy_hull:=10; var docked=false; var dock_name:=""; var cooldown:=0.0
var auto_fire:=true; var move_touch:=Vector2.ZERO; var aim_touch:=Vector2.ZERO; var left_id:=-1; var right_id:=-1
var left_origin:=Vector2.ZERO; var right_origin:=Vector2.ZERO; var message:="Launch and explore."
var btn_auto:=Rect2(); var btn_missile:=Rect2(); var btn_repair:=Rect2(); var btn_dock:=Rect2(); var btn_gate:=Rect2()
var btn_weapon:=Rect2(); var btn_ship:=Rect2(); var btn_launch:=Rect2()

func _ready():
	var keys={"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"fire":KEY_SPACE,"boost":KEY_SHIFT}
	for a in keys:
		if not InputMap.has_action(a): InputMap.add_action(a)
		var e=InputEventKey.new(); e.physical_keycode=keys[a]; InputMap.action_add_event(a,e)
	var env=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(0.004,0.008,0.025); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color(0.45,0.5,0.7); add_child(env)
	var sun=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-35,-35,0); add_child(sun)
	ship=make_body("Player",false,1.6,Color.CYAN); add_child(ship)
	camera=Camera3D.new(); camera.current=true; add_child(camera)
	var canvas=CanvasLayer.new(); add_child(canvas); hud=Label.new(); hud.position=Vector2(18,14); hud.add_theme_font_size_override("font_size",18); canvas.add_child(hud)
	load_system(0)

func make_body(n:String,sphere:bool,s:float,col:Color)->Node3D:
	var o=Node3D.new(); o.name=n; var m=MeshInstance3D.new(); m.mesh=SphereMesh.new() if sphere else BoxMesh.new(); m.scale=Vector3.ONE*s
	var mat=StandardMaterial3D.new(); mat.albedo_color=col; m.material_override=mat; o.add_child(m); return o

func add_body(n:String,pos:Vector3,sphere:bool,s:float,col:Color)->Node3D:
	var o=make_body(n,sphere,s,col); o.position=pos; world.add_child(o); return o

func load_system(id:int):
	if is_instance_valid(world): world.queue_free()
	world=Node3D.new(); add_child(world); system=id; docked=false; dock_name=""; ship.position=Vector3(0,0,18); ship.rotation=Vector3.ZERO
	if id==0:
		planet=add_body("New Terra",Vector3(-72,4,-115),true,10,Color(0.15,0.45,0.95))
		station=add_body("Liberty Hub",Vector3(-24,0,-38),false,8,Color(0.7,0.75,0.85))
		gate=add_body("Aquila Jump Gate",Vector3(72,0,-155),true,5,Color(0.15,0.8,1))
		enemy=add_body("Raider",Vector3(22,0,-64),false,2,Color(1,0.2,0.1)); enemy_hull=10
		add_asteroids(Vector3(25,0,-105),26); add_nebula(Vector3(-20,0,-145),Color(0.35,0.12,0.55))
		message="SOLARA: New Terra, Liberty Hub, asteroid belt, Violet Reach nebula, Aquila gate."
	else:
		planet=add_body("Eden Prime",Vector3(78,8,-125),true,12,Color(0.25,0.8,0.4))
		station=add_body("Frontier Exchange",Vector3(30,0,-48),false,9,Color(0.85,0.65,0.25))
		gate=add_body("Solara Jump Gate",Vector3(-75,0,-155),true,5,Color(0.15,0.8,1))
		enemy=add_body("Corsair",Vector3(-18,0,-70),false,2,Color(1,0.25,0.1)); enemy_hull=14
		add_asteroids(Vector3(-32,0,-112),30); add_nebula(Vector3(35,0,-150),Color(0.1,0.35,0.55))
		message="VEGA: Eden Prime, Frontier Exchange, ice belt, Azure Veil nebula, Solara gate."

func add_asteroids(center:Vector3,count:int):
	for i in count:
		var p=center+Vector3(sin(i*2.7)*32,cos(i*1.8)*10,cos(i*3.1)*35)
		add_body("Asteroid",p,true,0.8+float(i%4)*0.45,Color(0.38,0.35,0.32))

func add_nebula(center:Vector3,col:Color):
	for i in 9:
		var cloud=add_body("Nebula",center+Vector3(sin(i*1.9)*25,cos(i*2.2)*12,cos(i)*22),true,7+float(i%3)*3,col)
		var mesh=cloud.get_child(0) as MeshInstance3D; var mat=mesh.material_override as StandardMaterial3D; mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color.a=0.12

func _process(d:float):
	cooldown=maxf(0,cooldown-d); shield=minf(100,shield+d*5)
	if not docked:
		var turn=Input.get_action_strength("left")-Input.get_action_strength("right")-aim_touch.x
		ship.rotate_y(turn*d*1.8); var thrust=Input.get_action_strength("forward")-Input.get_action_strength("back")*.5-move_touch.y
		var speed=(46.0+ship_class*10.0)*(1.8 if Input.is_action_pressed("boost") else 1.0)
		ship.position-=ship.global_basis.z*thrust*speed*d; ship.position+=ship.global_basis.x*move_touch.x*speed*.7*d
		var lock=is_instance_valid(enemy) and ship.position.distance_to(enemy.position)<90 and (-ship.global_basis.z).dot((enemy.position-ship.position).normalized())>.90
		if (Input.is_action_pressed("fire") or (auto_fire and lock)) and cooldown<=0: shoot()
	var behind=ship.position+ship.global_basis.z*14+Vector3(0,6,0); camera.position=camera.position.lerp(behind,minf(1,d*5)); camera.look_at(ship.position-ship.global_basis.z*16,Vector3.UP)
	var place="DOCKED: "+dock_name if docked else ("SOLARA" if system==0 else "VEGA")
	hud.text="HOMELANCER DIGITAL — TWO SYSTEM TEST\n%s | CREDITS %d | HULL %d | SHIELD %d%% | REPAIRS %d | MISSILES %d\nSHIP %s | WEAPON Mk%d | FIRE %s\n%s"%[place,credits,hull,int(shield),repairs,missiles,ship_name(),weapon,"AUTO" if auto_fire else "MANUAL",message]
	queue_redraw()

func ship_name()->String: return ["CADET","RANGER","LANCER"][ship_class]

func shoot():
	cooldown=.22
	if not is_instance_valid(enemy): return
	var v=enemy.position-ship.position
	if v.length()<90 and (-ship.global_basis.z).dot(v.normalized())>.90:
		enemy_hull-=weapon
		if enemy_hull<=0: enemy.queue_free(); credits+=75; message="Enemy destroyed. +75 credits."

func fire_missile():
	if missiles<=0 or not is_instance_valid(enemy): return
	if ship.position.distance_to(enemy.position)<130:
		missiles-=1; enemy_hull-=5+weapon
		if enemy_hull<=0: enemy.queue_free(); credits+=75; message="Missile kill. +75 credits."

func use_repair():
	if repairs>0 and hull<100: repairs-=1; hull=mini(100,hull+35)

func try_dock():
	if docked:return
	if ship.position.distance_to(station.position)<20: enter_hub(station.name)
	elif ship.position.distance_to(planet.position)<24: enter_hub(planet.name)
	else: message="Move closer to a planet or station to dock."

func enter_hub(where:String):
	docked=true; dock_name=where; hull=100; shield=100; repairs=5; missiles=4; message="HUB: buy weapons/ships, repair/resupply, or launch."

func launch(): docked=false; dock_name=""; ship.position+=Vector3(0,0,18); message="Launch complete."

func buy_weapon():
	if not docked:return
	var cost=100*weapon
	if credits>=cost and weapon<4: credits-=cost; weapon+=1; message="Purchased Weapon Mk%d."%weapon
	else: message="Weapon purchase unavailable. Cost %d."%cost

func buy_ship():
	if not docked:return
	var cost=[300,600,99999][ship_class]
	if ship_class<2 and credits>=cost: credits-=cost; ship_class+=1; hull=100; shield=100; message="Purchased %s."%ship_name()
	else: message="Next ship costs %d credits."%cost

func jump_gate():
	if docked:return
	if ship.position.distance_to(gate.position)<22: load_system(1-system)
	else: message="Fly closer to the jump gate."

func _input(e:InputEvent):
	var s=get_viewport().get_visible_rect().size
	btn_auto=Rect2(s.x-190,18,170,48); btn_dock=Rect2(s.x-190,74,170,48); btn_gate=Rect2(s.x-190,130,170,48)
	btn_missile=Rect2(s.x-190,s.y-166,170,48); btn_repair=Rect2(s.x-190,s.y-110,170,48)
	btn_weapon=Rect2(s.x/2-260,s.y-70,160,50); btn_ship=Rect2(s.x/2-80,s.y-70,160,50); btn_launch=Rect2(s.x/2+100,s.y-70,160,50)
	if e is InputEventScreenTouch:
		if e.pressed:
			if docked:
				if btn_weapon.has_point(e.position): buy_weapon(); return
				if btn_ship.has_point(e.position): buy_ship(); return
				if btn_launch.has_point(e.position): launch(); return
			if btn_auto.has_point(e.position): auto_fire=!auto_fire; return
			if btn_dock.has_point(e.position): try_dock(); return
			if btn_gate.has_point(e.position): jump_gate(); return
			if btn_missile.has_point(e.position): fire_missile(); return
			if btn_repair.has_point(e.position): use_repair(); return
			if e.position.x<s.x*.5 and left_id<0: left_id=e.index; left_origin=e.position
			elif right_id<0: right_id=e.index; right_origin=e.position
		else:
			if e.index==left_id:left_id=-1;move_touch=Vector2.ZERO
			if e.index==right_id:right_id=-1;aim_touch=Vector2.ZERO
	elif e is InputEventScreenDrag:
		if e.index==left_id:move_touch=((e.position-left_origin)/90).limit_length(1)
		if e.index==right_id:aim_touch=((e.position-right_origin)/90).limit_length(1)

func button(r:Rect2,label:String,col:Color):
	draw_rect(r,col); draw_string(ThemeDB.fallback_font,r.position+Vector2(14,31),label,HORIZONTAL_ALIGNMENT_LEFT,r.size.x-20,17)

func _draw():
	var s=get_viewport().get_visible_rect().size
	draw_circle(Vector2(110,s.y-110),72,Color(0.1,0.5,0.8,.22)); draw_circle(Vector2(s.x-110,s.y-255),72,Color(0.8,0.5,0.1,.2))
	button(Rect2(s.x-190,18,170,48),"AUTO / MANUAL",Color(0.1,0.4,0.7,.55)); button(Rect2(s.x-190,74,170,48),"DOCK",Color(0.2,0.55,0.65,.55)); button(Rect2(s.x-190,130,170,48),"JUMP GATE",Color(0.4,0.25,0.75,.55))
	button(Rect2(s.x-190,s.y-166,170,48),"MISSILE",Color(0.7,0.3,0.1,.55)); button(Rect2(s.x-190,s.y-110,170,48),"REPAIR",Color(0.1,0.55,0.3,.55))
	if docked:
		draw_rect(Rect2(s.x/2-300,s.y-95,600,85),Color(0.02,0.04,0.09,.9))
		button(Rect2(s.x/2-260,s.y-70,160,50),"BUY WEAPON",Color(0.45,0.3,0.1,.8)); button(Rect2(s.x/2-80,s.y-70,160,50),"BUY SHIP",Color(0.15,0.4,0.65,.8)); button(Rect2(s.x/2+100,s.y-70,160,50),"LAUNCH",Color(0.1,0.55,0.3,.8))
