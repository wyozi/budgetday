AddCSLuaFile()

ENT.Base 			= "base_nextbot"
ENT.Spawnable		= true

ENT.Model = Model("models/Kleiner.mdl")

function ENT:GetSuspicionLevel()
	return self:GetNWFloat("Suspicion", 0) or 0
end
function ENT:SetSuspicionLevel(lvl)
	return self:SetNWFloat("Suspicion", lvl)
end

function ENT:Initialize()
	if SERVER then
		self:SetModel(self.Model)

		self:SetHealth(100)
	end
end

-- So confusing
function ENT:EyePosN()
	local headbone = self:LookupBone("ValveBiped.Bip01_Head1")
	local headpos = self:GetBonePosition(headbone)
	return headpos
end

function ENT:IsPointOnSight(p)
	--http://stackoverflow.com/questions/12826117/how-can-i-detect-if-a-point-is-inside-of-a-cone-or-not-in-3d-space

	local cone_tip = self:EyePosN()
	local cone_dir = self:EyeAngles():Forward()
	local cone_height = 1024

	local cone_base_radius = 512

	local p_tip_diff = p - cone_tip

	local cone_dist = p_tip_diff:Dot(cone_dir)
	if cone_dist < 0 or cone_dist > cone_height then return false end

	local cone_radius_at_point = (cone_dist / cone_height) * cone_base_radius
	local orth_dist =  (p_tip_diff - cone_dist * cone_dir):Length()

	return orth_dist < cone_radius_at_point
end

if SERVER then
	function ENT:AddFlashlight()
		local shootpos = self:GetAttachment(self:LookupAttachment("anim_attachment_LH"))

		local wep = ents.Create("bd_lamp")
		wep:SetModel(Model("models/maxofs2d/lamp_flashlight.mdl"))
		wep:SetOwner(self)

		wep:SetFlashlightTexture("effects/flashlight/soft")
		wep:SetColor(Color(255, 255, 255))
		wep:SetDistance(512)
		wep:SetBrightness(1)
		wep:SetLightFOV(80)
	    wep:Switch(true)

	    wep:Spawn()

	    wep:SetModelScale(0.5, 0)
	    
	    wep:SetSolid(SOLID_NONE)
	    wep:SetParent(self)

	    wep:Fire("setparentattachment", "anim_attachment_LH")

	    self.Flashlight = wep
	end

	function ENT:AddFakeWeapon(model)
		local shootpos = self:GetAttachment(self:LookupAttachment("anim_attachment_RH"))

		local wep = ents.Create("prop_physics")
		wep:SetModel(model)
		wep:SetOwner(self)
		wep:SetPos(shootpos.Pos)
	    --wep:SetAngles(ang)
	    wep:Spawn()
	    
	    wep:SetSolid(SOLID_NONE)
	    wep:SetParent(self)

	    wep:Fire("setparentattachment", "anim_attachment_RH")
	    wep:AddEffects(EF_BONEMERGE)
	    wep:SetAngles(self:GetForward():Angle())

	    self.PhysWeapon = wep

	    -- If we had a flashlight, we remove that and attach a flashlight to our weapon
	    if IsValid(self.Flashlight) then
	    	self.Flashlight:Remove()

	    	-- TODO attach flashlight
	    end
	end

	function ENT:BehaveAct()

	end
	function ENT:MoveToPos( pos, options )
		local options = options or {}

		local path = Path( "Follow" )
		path:SetMinLookAheadDistance( options.lookahead or 300 )
		path:SetGoalTolerance( options.tolerance or 20 )
		path:Compute( self, pos )

		if ( !path:IsValid() ) then return "failed" end

		while ( path:IsValid() ) do
			if options.terminate_condition and options.terminate_condition() then
				return "terminated"
			end

			path:Update( self )

			-- Draw the path (only visible on listen servers or single player)
			if ( options.draw ) then
				path:Draw()
			end

			-- If we're stuck then call the HandleStuck function and abandon
			if ( self.loco:IsStuck() ) then
				self:HandleStuck()
				return "stuck"
			end

			--
			-- If they set maxage on options then make sure the path is younger than it
			--
			if ( options.maxage ) then
				if ( path:GetAge() > options.maxage ) then return "timeout" end
			end

			--
			-- If they set repath then rebuild the path every x seconds
			--
			if ( options.repath ) then
				if ( path:GetAge() > options.repath ) then
					local newpos = (options.repath_pos and options.repath_pos() or pos)
					path:Compute( self, newpos )
				end
			end

			coroutine.yield()
		end
		return "ok"
	end

	-- This is the method you need to override
	function ENT:BehaviourTick()
		self:StartActivity(ACT_IDLE)
	end

	function ENT:RunBehaviour()
		while ( true ) do
			local stat, err = pcall(function() self:BehaviourTick() end)

			if not stat then MsgN("NextBot error: ", err) end

			coroutine.yield()
		end
	end

	function ENT:Think()
		if IsValid(self.Flashlight) then
			local shootpos = self:GetAttachment(self:LookupAttachment("anim_attachment_LH"))
			local pos, ang = shootpos.Pos, shootpos.Ang
			ang:RotateAroundAxis(ang:Right(), 180)
			self.Flashlight:SetAngles(ang)
		end
	end

	function ENT:UpdateTransmitState()
		return TRANSMIT_ALWAYS
	end

	function ENT:NotifyDistraction(data)
		self:SetSuspicionLevel(self:GetSuspicionLevel() + data.level)

		self.DistractionHistory = self.DistractionHistory or {}
		
		table.insert(self.DistractionHistory, {
			happened = CurTime(),
			data = data
		})

		hook.Call("BDNextbotDistraction", GAMEMODE, self, data)
	end

	-- Once again some nice code from TTT..
	function ENT:BecomePhysicalRagdoll(dmginfo)

		local rag = ents.Create("prop_ragdoll")
		if not IsValid(rag) then return nil end

		rag:SetPos(self:GetPos())
		rag:SetModel(self:GetModel())
		rag:SetAngles(self:GetAngles())
		rag:Spawn()
		rag:Activate()

		-- nonsolid to players, but can be picked up and shot
		rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)

		-- position the bones
		local num = rag:GetPhysicsObjectCount()-1
		local v = self:GetVelocity()
		-- bullets have a lot of force, which feels better when shooting props,
		-- but makes bodies fly, so dampen that here
		if dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_SLASH) then
			v = v / 5
		end
		for i=0, num do
			local bone = rag:GetPhysicsObjectNum(i)
			if IsValid(bone) then
				local bp, ba = self:GetBonePosition(rag:TranslatePhysBoneToBone(i))
				if bp and ba then
					bone:SetPos(bp)
					bone:SetAngles(ba)
				end
				-- not sure if this will work:
				bone:SetVelocity(v)
			end
		end

	end

	function ENT:OnInjured(dmginfo)
		local pos = dmginfo:GetDamagePosition()

		local hitgroup = 0
		debugoverlay.Sphere(pos, 6, 1)
		if dmginfo:IsBulletDamage() then
			self:NotifyDistraction({level = 1, pos = dmginfo:GetDamagePosition(), cause = "Was damaged"})
		end
	end

	function ENT:OnKilled( dmginfo )
		self:BecomePhysicalRagdoll( dmginfo )
		self:Remove()
	end
end