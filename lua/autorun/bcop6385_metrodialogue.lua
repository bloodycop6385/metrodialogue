MsgC( Color( 190, 255, 255 ), "[ MetroDialogue ] Loading...!\n" )

MetroDialogue = MetroDialogue or {}
MetroDialogue.MultiResponderChance = MetroDialogue.MultiResponderChance or 0.5
MetroDialogue.ResponseGap = MetroDialogue.ResponseGap or 0.15

local function entsInCube( center, radius )
	if ( !isvector( center ) ) then
		return error( "Invalid argument: 'center' must be a Vector" )
	end

	if ( !isnumber( radius ) or radius <= 0 ) then
		return error( "Invalid argument: 'radius' must be a positive number" )
	end

	local rvec = Vector( radius, radius, radius )

	return ents.FindInBox( center - rvec, center + rvec )
end

MetroDialogue.Lines = {
	{
		soundPath = "metrodialogue/h6bridge.wav",
		text = "Hey, did you hear about about HERO-6 ? I believe he jumped off a bridge.",

		responses = {
			{ soundPath = "metrodialogue/precintlostmind.wav", text = "Bloody hell, even the precinct's losing it's mind." }
		},

		canSay = false
	},
	{
		soundPath = "metrodialogue/imaginebeingcitizen.wav",
		text = "Imagine still being a citizen.",

		responses = {
			{ soundPath = "metrodialogue/mhm.wav", text = "<i>Mhm.</i>" }
		},

		canSay = false
	},
	{
		soundPath = "metrodialogue/bestcareerchoice.wav",
		text = "THIS was definitely the best career choice, I've ever made.",

		responses = {
			{ soundPath = "metrodialogue/tellmeaboutit.wav", text = "Tell me about it." }
		},

		canSay = false
	},
	{
		soundPath = "metrodialogue/politics.wav",
		text = "Soo.. What do you guys think about politics?",

		responses = {
			{ soundPath = "metrodialogue/leave.wav", text = "<i>Ugh..<i> Leave my patrol team, right now." },
			{ soundPath = "metrodialogue/tellmeaboutit.wav", text = "Tell me about it." }
		},

		requiresGroup = true
	}
}

if ( SERVER ) then
	util.AddNetworkString( "MetroDialogue_Caption" )

	function MetroDialogue.InitialiseTimer( entity )
		local timerID = "MetroDialogue_NPCInit_" .. entity:EntIndex()

		timer.Create( timerID, 5, 0, function()
			if ( !IsValid( entity ) ) then
				timer.Remove( timerID )
				return
			end

			local entTable = entity:GetTable()
			if ( !istable( entTable ) ) then
				timer.Remove( timerID )
				return
			end

			local listeners = {}
			local nearby = entsInCube( entity:GetPos(), 256 )

			for i = 1, #nearby do
				local e = nearby[ i ]

				if ( e:IsNPC() and e != entity and e:GetClass() == "npc_metropolice" ) then
					listeners[ #listeners + 1 ] = e
				end
			end

			if ( listeners[1] == nil ) then return end

			-- Elect a single initiator (lowest EntIndex) to avoid simultaneous starts
			local minIdx = entity:EntIndex()

			for i = 1, #listeners do
				local idx = listeners[i]:EntIndex()
				if ( idx < minIdx ) then minIdx = idx end
			end

			if ( entity:EntIndex() != minIdx ) then return end

			local shouldPlay = hook.Run( "MetroDialogue_ShouldPlay", entity, listeners )
			if ( shouldPlay == false ) then return end

			-- Choose a random initiator (speaker) from the whole group (entity + listeners)
			local participants = { entity }
			for i = 1, #listeners do participants[#participants + 1] = listeners[i] end

			local pick = math.random( 1, #participants )
			local chosenSpeaker = participants[ pick ]

			local chosenListeners = {}
			for i = 1, #participants do
				local p = participants[i]
				if ( p != chosenSpeaker ) then
					chosenListeners[ #chosenListeners + 1 ] = p
				end
			end

			-- Only proceed if the chosen speaker can actually talk right now
			if ( !MetroDialogue.CanSpeak( chosenSpeaker ) ) then return end

			local before = chosenSpeaker:GetTable().MetroDialogue_SpeakingUntil or 0
			MetroDialogue.Play( chosenSpeaker, chosenListeners )
			local after = chosenSpeaker:GetTable().MetroDialogue_SpeakingUntil or 0

			if ( after > before ) then
				print( "[ MetroDialogue ] " .. tostring( chosenSpeaker ) .. " is starting a conversation with " .. #chosenListeners .. " listeners." )
				-- Spread out subsequent attempts for this scheduler to avoid bursts
				timer.Adjust( timerID, math.random( 10, 30 ) )
			end

			--timer.Adjust( timerID, math.random( 10, 300 ) )
		end)

		return timerID
	end

	-- Safe duration helper: uses SoundDuration when available, else falls back to text length or a default
	function MetroDialogue.SafeSoundDuration( soundPath, text )
		local dur = 0
		if ( isstring( soundPath ) and #soundPath > 0 ) then
			local ok, sd = pcall( SoundDuration, soundPath )
			if ( ok and isnumber( sd ) and sd > 0 ) then dur = sd end
		end

		if ( dur <= 0 ) then
			if ( isstring( text ) and #text > 0 ) then
				dur = math.Clamp( #text * 0.06, 1.0, 4.0 )
			else
				dur = 1.5
			end
		end

		return dur
	end

	function MetroDialogue.CanSpeak( npc, opts )
		opts = opts or {}

		if ( !npc:IsNPC() or npc:GetClass() != "npc_metropolice" ) then return false end

		if ( !opts.ignoreIdle and !npc:IsCurrentSchedule( SCHED_IDLE_STAND ) ) then return false end

		local npcTable = npc:GetTable()
		if ( !istable( npcTable ) ) then return false end

		if ( npcTable.IsSpeakingCoreChatter ) then return false end
		if ( !opts.ignoreSpeakingUntil and isnumber( npcTable.MetroDialogue_SpeakingUntil ) and CurTime() < npcTable.MetroDialogue_SpeakingUntil ) then return false end
		if ( !opts.ignorePartners and istable( npcTable.MetroDialogue_DialoguePartners ) and npcTable.MetroDialogue_DialoguePartners[1] != nil ) then return false end

		return true
	end

	-- Helper to clear dialogue partners for a set of participants without nesting pyramids
	function MetroDialogue.ClearDialoguePartners( participants )
		if ( !istable( participants ) ) then return end

		for i = 1, #participants do
			local p = participants[i]

			if ( IsValid( p ) ) then
				local t = p:GetTable()

				if ( istable( t ) ) then
					t.MetroDialogue_DialoguePartners = {}
				end
			end
		end
	end

	-- Group requirement helper: supports boolean (true means >=3) or numeric threshold
	function MetroDialogue.IsGroupAllowed( requiresGroup, participantCount )
		if ( requiresGroup == nil ) then return true end

		if ( isbool( requiresGroup ) ) then
			return ( requiresGroup == false ) or ( participantCount >= 3 )
		end

		if ( isnumber( requiresGroup ) ) then
			return participantCount >= requiresGroup
		end

		return true
	end

	-- Returns responses that are eligible for the current participant count (and optional canSay checks)
	function MetroDialogue.GetAllowedResponses( responses, speaker, listeners, participants, line )
		local out = {}

		if ( istable( responses ) ) then
			for i = 1, #responses do
				local resp = responses[i]

				if ( istable( resp ) and MetroDialogue.IsGroupAllowed( resp.requiresGroup, #participants ) ) then
					local ok = true

					if ( isfunction( resp.canSay ) ) then
						ok = resp:CanSay( speaker, listeners, participants, line ) == true
					elseif ( isbool( resp.canSay ) ) then
						ok = resp.canSay == true
					end

					if ( ok ) then
						out[ #out + 1 ] = resp
					end
				end
			end
		end

		return out
	end

	-- Helper to perform a listener's reply (reduces nesting inside timers)
	function MetroDialogue.ResponderSpeak( responder, response, participants, respDur )
		if ( !IsValid( responder ) ) then return end
		local t = responder:GetTable()
		if ( !istable( t ) ) then return end
		t.MetroDialogue_SpeakingUntil = CurTime() + respDur + 0.1
		t.MetroDialogue_DialoguePartners = participants
		responder:EmitSound( response.soundPath or "", 75, 100, 1, CHAN_VOICE )
		MetroDialogue.Caption( responder, response.text or "" )
	end

	function MetroDialogue.Play( speaker, listeners )
		-- Compute participant count up-front
		local participantCount = 1 + #listeners

		-- Precompute a participant list for validation
		local tmpParticipants = { speaker }
		for i = 1, #listeners do tmpParticipants[#tmpParticipants + 1] = listeners[i] end

		-- Pick a line that satisfies group requirements and optional canSay
		local allowedLines = {}
		for i = 1, #MetroDialogue.Lines do
			local line = MetroDialogue.Lines[i]

			if ( istable( line ) and MetroDialogue.IsGroupAllowed( line.requiresGroup, participantCount ) ) then
				local ok = true

				if ( isfunction( line.canSay ) ) then
					ok = line:canSay( speaker, listeners, tmpParticipants, line ) == true
				elseif ( isbool( line.canSay ) ) then
					ok = line.canSay == true
				end

				if ( ok ) then
					allowedLines[ #allowedLines + 1 ] = line
				end
			end
		end

		if ( allowedLines[1] == nil ) then return end

		local randomDialogue = table.Copy( allowedLines[ math.random( #allowedLines ) ] )
		if ( !istable( randomDialogue ) ) then return end

		randomDialogue = hook.Run( "MetroDialogue_ModifyLine", speaker, listeners, randomDialogue ) or randomDialogue
		if ( !istable( randomDialogue ) ) then return end

		if ( !MetroDialogue.CanSpeak( speaker ) ) then return end

		local speakerTable = speaker:GetTable()
		local speakDur = MetroDialogue.SafeSoundDuration( randomDialogue.soundPath, randomDialogue.text )

		-- Mark all participants as engaged immediately
		local participants = { speaker }
		for i = 1, #listeners do participants[#participants + 1] = listeners[i] end

		for i = 1, #participants do
			local p = participants[i]
			local t = p:GetTable()

			if ( istable( t ) ) then
				t.MetroDialogue_DialoguePartners = participants
			end
		end

		-- Prevent listeners from starting their own convo while the speaker talks
		for i = 1, #listeners do
			local lt = listeners[i]:GetTable()

			if ( istable( lt ) ) then
				lt.MetroDialogue_SpeakingUntil = CurTime() + speakDur + 0.1
			end
		end

		speakerTable.MetroDialogue_SpeakingUntil = CurTime() + speakDur + 0.1

		speaker:EmitSound( randomDialogue.soundPath or "", 75, 100, 1, CHAN_VOICE )
		MetroDialogue.Caption( speaker, randomDialogue.text or "" )

		local listenerTable = nil

		if ( listeners[ 2 ] != nil ) then
			timer.Simple( speakDur + 0.2, function()
				if ( !IsValid( speaker ) ) then return end

				-- Build eligible candidates
				local candidates = {}
				for i = 1, #listeners do
					local listener = listeners[ i ]
					if ( IsValid( listener ) and MetroDialogue.CanSpeak( listener, { ignorePartners = true } ) ) then
						candidates[ #candidates + 1 ] = listener
					end
				end

				if ( candidates[1] == nil ) then
					MetroDialogue.ClearDialoguePartners( participants )
					return
				end

				local allowedResponses = MetroDialogue.GetAllowedResponses( randomDialogue.responses, speaker, listeners, participants, randomDialogue )
				if ( allowedResponses[1] == nil ) then
					MetroDialogue.ClearDialoguePartners( participants )
					return
				end

				-- Choose primary responder randomly, then optionally queue more based on chance
				local order = {}
				local primaryIndex = math.random( 1, #candidates )
				order[1] = candidates[ primaryIndex ]

				for i = 1, #candidates do
					if ( i == primaryIndex ) then continue end
					if ( math.Rand( 0, 1 ) < ( MetroDialogue.MultiResponderChance or 0.5 ) ) then
						order[ #order + 1 ] = candidates[ i ]
					end
				end

				-- Schedule responses sequentially to avoid overlap
				local chainOffset = 0
				for i = 1, #order do
					local responder = order[ i ]
					local response = allowedResponses[ math.random( #allowedResponses ) ]
					local respDur = MetroDialogue.SafeSoundDuration( response.soundPath, response.text )
					local startDelay = chainOffset

					timer.Simple( startDelay, function()
						MetroDialogue.ResponderSpeak( responder, response, participants, respDur )
					end)

					chainOffset = chainOffset + respDur + ( MetroDialogue.ResponseGap or 0.15 )
				end

				-- Clear partners after the last scheduled response
				timer.Simple( chainOffset + 0.2, function()
					MetroDialogue.ClearDialoguePartners( participants )
				end)
			end)

			return
		end

		-- Single-listener path: wait for the SPEAKER's duration, not the response duration
		-- We will choose an eligible response after the speaker finishes
		local listener = listeners[ 1 ]

		timer.Simple( speakDur + 0.2, function()
			if ( !IsValid( listener ) ) then return end
			if ( !MetroDialogue.CanSpeak( listener, { ignorePartners = true } ) ) then return end

			listenerTable = listener:GetTable()
			if ( !istable( listenerTable ) ) then return end

			local allowedResponses = MetroDialogue.GetAllowedResponses( randomDialogue.responses, speaker, listeners, participants, randomDialogue )
			if ( allowedResponses[1] == nil ) then
				MetroDialogue.ClearDialoguePartners( participants )
				return
			end

			local response = allowedResponses[ math.random( #allowedResponses ) ]
			local respDur = MetroDialogue.SafeSoundDuration( response.soundPath, response.text )

			listenerTable.MetroDialogue_SpeakingUntil = CurTime() + respDur + 0.1
			listener:EmitSound( response.soundPath or "", 75, 100, 1, CHAN_VOICE )
			MetroDialogue.Caption( listener, response.text or "" )

			-- Clear partners when the response ends
			timer.Simple( respDur + 0.2, function()
				MetroDialogue.ClearDialoguePartners( participants )
			end)
		end)

	end

	-- Client caption sender
	function MetroDialogue.Caption( speaker, sentence )
		net.Start( "MetroDialogue_Caption" )
			net.WriteEntity( speaker )
			net.WriteString( sentence )
			net.WriteColor( speaker:GetTable().MetroDialogue_DialogueColour or Color( 255, 255, 255 ) )
		net.SendPVS( speaker:GetPos() )
	end

	hook.Add( "OnEntityCreated", "MetroDialogue_NPCInit", function( ent )
		if ( !IsValid( ent ) or !ent:IsNPC() ) then return end
		if ( ent:GetClass() != "npc_metropolice" ) then return end

		local entTable = ent:GetTable()
		if ( !istable( entTable ) ) then return end

		entTable.MetroDialogue_SpeakingUntil = 0
		entTable.MetroDialogue_DialoguePartners = {}
		entTable.MetroDialogue_DialogueColour = Color( math.random( 0, 255 ), math.random( 0, 255 ), math.random( 0, 255 ) )

		MetroDialogue.InitialiseTimer( ent )
	end )

	hook.Add( "OnEntityRemoved", "MetroDialogue_NPCCleanup", function( ent )
		if ( !IsValid( ent ) or !ent:IsNPC() ) then return end
		if ( ent:GetClass() != "npc_metropolice" ) then return end

		local timerID = "MetroDialogue_NPCInit_" .. ent:EntIndex()
		timer.Remove( timerID )
	end )

	hook.Add( "EntityEmitSound", "MetroDialogue_EntityEmitSound", function( data )
		local entity = data.Entity
		if ( !IsValid( entity ) or !entity:IsNPC() or entity:GetClass() != "npc_metropolice" ) then return end

		local soundPath = data.SoundName

		local entTable = entity:GetTable()
		if ( !istable( entTable ) ) then return end

		if ( string.find( soundPath, "metrodialogue/" ) != nil and entTable.IsSpeakingCoreChatter ) then
			return false
		end

		if ( string.find( data.OriginalSoundName, "METROPOLICE" ) != nil ) then
			if ( isnumber( entTable.MetroDialogue_SpeakingUntil ) and CurTime() < entTable.MetroDialogue_SpeakingUntil ) then
				return false
			end

			entTable.IsSpeakingCoreChatter = true

			timer.Simple( MetroDialogue.SafeSoundDuration( soundPath ) + 0.1, function()
				if ( !IsValid( entity ) ) then return end

				entTable = entity:GetTable()
				if ( !istable( entTable ) ) then return end

				entTable.IsSpeakingCoreChatter = false
			end)
		end
	end)
else
	net.Receive( "MetroDialogue_Caption", function()
		local npc = net.ReadEntity()
		if ( !IsValid( npc ) ) then return end

		if ( npc:IsDormant() or !LocalPlayer():IsLineOfSightClear(npc) ) then return end
		if ( npc:GetPos():DistToSqr( LocalPlayer():GetPos() ) > 350 ^ 2 ) then return end

		local sentence = net.ReadString()
		if ( !isstring( sentence ) or #sentence == 0 ) then return end

		local captionDuration = #sentence * 0.1
		local colour = net.ReadColor()

		sentence = "<clr:" .. colour.r .. "," .. colour.g .. "," .. colour.b .. ">" .. sentence

		gui.AddCaption( sentence, captionDuration )
	end)

	local metrocops = ents.FindByClass( "npc_metropolice" )
	for i = 1, #metrocops do
		local cop = metrocops[i]

		local timerID = "MetroDialogue_NPCInit_" .. cop:EntIndex()
		if ( timer.Exists( timerID ) ) then
			timer.Remove( timerID )
			MetroDialogue.InitialiseTimer( cop )
		end
	end
end
