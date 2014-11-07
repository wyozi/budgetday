
local brain_generic = {
	CheckForCameras = function(self, pos, dir, spotter_ent, callback, checked_monitors)
		checked_monitors = checked_monitors or {}

		callback(pos, dir, spotter_ent)

		local check_ents = ents.FindByClass("bd_camera_monitor")

		for _,ce in pairs(check_ents) do
			if table.HasValue(checked_monitors, ce) then continue end

			local pos_diff = (ce:GetPos() - pos)
			local pos_diff_normal = pos_diff:GetNormalized()
			local dot = dir:Dot(pos_diff_normal)
			local dist = pos_diff:Length()

			if dist < 512 and dot > 0.25 then
				table.insert(checked_monitors, ce)
				local acam = ce:GetActiveCamera()
				if IsValid(acam) then
					local cpos, cang = acam:GetCameraPosAng()
					self:CheckForCameras(cpos, cang:Forward(), ce, callback, checked_monitors)
				end
			end

		end
	end,
	SpotEntities = function(self, pos, dir, spotter_ent)
		local check_ents = {}
		table.Add(check_ents, player.GetAll())
		table.Add(check_ents, ents.FindByClass("prop_ragdoll"))

		for _,ce in pairs(check_ents) do
			local targpos = ce:GetPos()
			if ce:IsPlayer() then
				targpos = ce:EyePos()
			end

			local pos_diff = (targpos - pos)
			local pos_diff_normal = pos_diff:GetNormalized()
			local dot = dir:Dot(pos_diff_normal)
			local dist = pos_diff:Length()

			local is_los_clear = ce:IsLineOfSightClear(pos)

			-- is_los_clear failed (fails on eg ragdolls) so we try to do LOS check the other way
			if is_los_clear == nil then
				is_los_clear = spotter_ent:IsLineOfSightClear(targpos)
			end

			if dist < 512 and dot > 0.6 and is_los_clear then
				--MsgN(ce, " getting spotted")
				debugoverlay.Line(pos, targpos, 0.1, Color(255, 0, 0), true)
			end
		end
	end,
	SpotPosition = function(self, ent)
		self:CheckForCameras(ent:GetPos() + Vector(0,0,60), ent:GetAngles():Forward(), ent, function(pos, dir, spotter_ent)
			self:SpotEntities(pos, dir, spotter_ent)
		end)
	end,
	Think = function(self, data, ent)
		local stat, err = pcall(function()
			self:SpotPosition(ent)

			if data.type == "roaming" and (not data.NextRoam or data.NextRoam < CurTime()) then
				ent.loco:SetAcceleration(100)
				ent.loco:SetDesiredSpeed(100)
				ent.loco:SetDeathDropHeight(40)
				ent:StartActivity(ACT_WALK)
				local p = table.Random(ents.FindByClass("bd_npc_poi")):GetPos()
				ent:MoveToPos(p, {
					terminate_condition = function()
						self:SpotPosition(ent)
						return false
					end}
				)

				data.NextRoam = CurTime() + math.random(2, 15)
			end

			--data.IdleSequence = data.IdleSequence or ("LineIdle0" .. math.random(1, 2))
			--ent:SetSequence(data.IdleSequence)

			ent:StartActivity(ACT_IDLE)
		end)
		if not stat then MsgN(err) end
		return CurTime()
	end
}

local function SpawnMapNPCs()
	local spawner_ents = ents.FindByClass("bd_npc_spawn")

	for _,spawner in pairs(spawner_ents) do
		local t = spawner:GetGuardType()

		local npc = ents.Create("bd_ai_base")
		npc:SetPos(spawner:GetPos())
		npc:SetAngles(spawner:GetAngles())

		npc:SetBrain(brain_generic)
		npc.BrainData.type = t

		npc:Activate()
		npc:Spawn()

		npc:AddFlashlight()
	end
end

hook.Add("BDRoundStateChanged", "SpawnMapNPCs", function(old_state, state)
	if state == "active" then
		SpawnMapNPCs()
	end
end)