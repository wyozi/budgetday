
-- Normal GMod movement is too flexible
hook.Add("SetupMove", "BD_NerfMovement", function( ply, mv, cmd )
	if mv:KeyDown(IN_JUMP) and (mv:GetVelocity():Length() > 175 or mv:KeyDown(IN_DUCK)) and ply:GetMoveType() == MOVETYPE_WALK then
		mv:SetVelocity(mv:GetVelocity():GetNormalized() * 175)
	end
end)

function GM:PlayerFootstep(ply, pos, foot, sound, volume, filter)
	if ply:KeyDown(IN_DUCK) then return true end
end
