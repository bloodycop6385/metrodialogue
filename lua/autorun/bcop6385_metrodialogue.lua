MsgC( Color( 190, 255, 255 ), "[ MetroDialogue ] Loading...!\n" )

MetroDialogue = MetroDialogue or {}
MetroDialogue.MultiResponderChance = MetroDialogue.MultiResponderChance or 0.5
MetroDialogue.ResponseGap = MetroDialogue.ResponseGap or 0.15
MetroDialogue.SearchRadius = MetroDialogue.SearchRadius or 256
MetroDialogue.MinGroupSize = MetroDialogue.MinGroupSize or 3
MetroDialogue.CharRate = MetroDialogue.CharRate or 0.06
MetroDialogue.MinLineDur = MetroDialogue.MinLineDur or 1.0
MetroDialogue.MaxLineDur = MetroDialogue.MaxLineDur or 4.0
MetroDialogue.MinDelayBetweenChats = MetroDialogue.MinDelayBetweenChats or 2.0
MetroDialogue.MaxDelayBetweenChats = MetroDialogue.MaxDelayBetweenChats or 10.0

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
	},
	{
		soundPath = "metrodialogue/imaginebeingcitizen.wav",
		text = "Imagine still being a citizen.",

		responses = {
			{ soundPath = "metrodialogue/mhm.wav", text = "<i>Mhm.</i>" }
		},
	},
	{
		soundPath = "metrodialogue/bestcareerchoice.wav",
		text = "THIS was definitely the best career choice, I've ever made.",

		responses = {
			{ soundPath = "metrodialogue/tellmeaboutit.wav", text = "Tell me about it." }
		},
	},
	{
		soundPath = "metrodialogue/politics.wav",
		text = "Soo.. What do you guys think about politics?",

		responses = {
			{ soundPath = "metrodialogue/leave.wav", text = "<i>Ugh..<i> Leave my patrol team, right now." },
			{ soundPath = "metrodialogue/tellmeaboutit.wav", text = "Tell me about it." }
		},

		requiresGroup = 3
	},
	{
		soundPath = "metrodialogue/ihateyou.wav",
		text = "I hate you.",
		responses = {
			{ soundPath = "metrodialogue/enjoyyourcompany.wav", text = "I'm enjoying your company as well." }
		},
	}
}

function MetroDialogue.AddDialogue( tLineData )
	if ( istable( tLineData ) ) then
		MetroDialogue.Lines[ #MetroDialogue.Lines + 1 ] = tLineData
	else
		error( "Invalid argument: 'tLineData' must be a table" )

		-- Complete template with all available options:
		--[[
		local exampleLine = {
			-- Required properties:
			soundPath = "metrodialogue/example.wav",     -- Path to sound file
			text = "Example line",                        -- Caption text (supports HTML tags)
			
			-- Optional line-level filters:
			canSay = function(speaker, listeners, participants, line)
				-- Custom logic to determine if this line can be spoken
				-- Return true to allow, false to block
				return true
			end,
			requiresGroup = 2,              -- Number: minimum participants needed, or true (uses cvar default, usually 3)
			shouldBeAlone = false,          -- Boolean: true = requires zero listeners (monologue), false/nil = requires listeners
			searchRadius = 300,             -- Number: override search radius for finding participants (default: 256)
			includeSchedules = {            -- Table: speaker must be in one of these schedules
				[SCHED_IDLE_STAND] = true,
			},
			excludeSchedules = {
				[SCHED_AMBUSH] = true,
			},
			
			-- Responses (optional):
			responses = {
				{
					-- Required response properties:
					soundPath = "metrodialogue/response.wav",
					text = "Response text",
					
					-- Optional response-level filters:
					canSay = function(speaker, listeners, participants, line, response)
						-- Custom logic for this specific response
						-- Has access to both the original line and this response
						return true
					end,
if ( SERVER ) then
	util.AddNetworkString( "MetroDialogue_Caption" )

	-- Server tunables (can be overridden by ConVars)
	local cvar_multi = CreateConVar( "metrodialogue_multi_chance", "0.5", FCVAR_ARCHIVE, "Chance an additional listener will also respond" )
	local cvar_gap = CreateConVar( "metrodialogue_response_gap", "0.15", FCVAR_ARCHIVE, "Gap between sequential listener responses (seconds)" )
	local cvar_search = CreateConVar( "metrodialogue_search_radius", "256", FCVAR_ARCHIVE, "Search radius for finding group participants (units)" )
	local cvar_min_group = CreateConVar( "metrodialogue_min_group", "3", FCVAR_ARCHIVE, "Minimum participants to satisfy boolean requiresGroup" )
	local cvar_char_rate = CreateConVar( "metrodialogue_char_rate", "0.06", FCVAR_ARCHIVE, "Seconds per character when estimating sound duration fallback" )
	local cvar_min_line = CreateConVar( "metrodialogue_min_line_dur", "1.0", FCVAR_ARCHIVE, "Minimum fallback duration for lines (seconds)" )
	local cvar_max_line = CreateConVar( "metrodialogue_max_line_dur", "4.0", FCVAR_ARCHIVE, "Maximum fallback duration for lines (seconds)" )
	-- Delay tunables (reserved for future scheduling adjustments)
	local cvar_min_delay = CreateConVar( "metrodialogue_min_delay_between_chats", "2.0", FCVAR_ARCHIVE, "Minimum delay between chat attempts (seconds)" )
	local cvar_max_delay = CreateConVar( "metrodialogue_max_delay_between_chats", "10.0", FCVAR_ARCHIVE, "Maximum delay between chat attempts (seconds)" )

	MetroDialogue.MinDelayBetweenChats = MetroDialogue.MinDelayBetweenChats or cvar_min_delay:GetFloat()
	MetroDialogue.MaxDelayBetweenChats = MetroDialogue.MaxDelayBetweenChats or cvar_max_delay:GetFloat()

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
			local radius = ( cvar_search and cvar_search:GetFloat() ) or ( MetroDialogue.SearchRadius or 256 )
			local nearby = entsInCube( entity:GetPos(), radius )

			for i = 1, #nearby do
				local e = nearby[ i ]

				if ( e:IsNPC() and e != entity and e:GetClass() == "npc_metropolice" ) then
					listeners[ #listeners + 1 ] = e
				end
			end

			-- Allow progression even with zero listeners to support 'shouldBeAlone' monologues

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

			print( "[ MetroDialogue ] " .. tostring( chosenSpeaker ) .. " wants to start a conversation with " .. #chosenListeners .. " listeners." )

			local before = chosenSpeaker:GetTable().MetroDialogue_SpeakingUntil or 0
			MetroDialogue.Play( chosenSpeaker, chosenListeners )
			local after = chosenSpeaker:GetTable().MetroDialogue_SpeakingUntil or 0

			if ( after > before ) then
				print( "[ MetroDialogue ] " .. tostring( chosenSpeaker ) .. " is starting a conversation with " .. #chosenListeners .. " listeners." )
				-- Spread out subsequent attempts for this scheduler to avoid bursts
				timer.Adjust( timerID, math.random( 10, 30 ) )
			end

			--timer.Adjust( timerID, math.random( cvar_min_delay:GetFloat(), cvar_max_delay:GetFloat() ) )
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
			local rate = ( cvar_char_rate and cvar_char_rate:GetFloat() ) or ( MetroDialogue.CharRate or 0.06 )
			local minDur = ( cvar_min_line and cvar_min_line:GetFloat() ) or ( MetroDialogue.MinLineDur or 1.0 )
			local maxDur = ( cvar_max_line and cvar_max_line:GetFloat() ) or ( MetroDialogue.MaxLineDur or 4.0 )

			if ( isstring( text ) and #text > 0 ) then
				dur = math.Clamp( #text * rate, minDur, maxDur )
			else
				dur = minDur
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

	-- Helpers for dynamic search radius
	function MetroDialogue.GetDefaultSearchRadius()
		return ( cvar_search and cvar_search:GetFloat() ) or ( MetroDialogue.SearchRadius or 256 )
	end

	function MetroDialogue.GetNearbyMetropolice( center, radius )
		if ( !IsValid( center ) ) then return {} end
		radius = radius or MetroDialogue.GetDefaultSearchRadius()

		local out = {}
		local nearby = entsInCube( center:GetPos(), radius )

		for i = 1, #nearby do
			local e = nearby[i]
			if ( e != center and e:IsNPC() and e:GetClass() == "npc_metropolice" ) then
				out[#out + 1] = e
			end
		end

		return out
	end

	-- Compute allowed responses for a specific responder, honoring response.searchRadius (fallback to line/search defaults)
	function MetroDialogue.ComputeAllowedResponsesFor( responder, line, speaker )
		local allowed = {}
		if ( !IsValid( responder ) or !istable( line ) or !istable( line.responses ) ) then return allowed end

		for r = 1, #line.responses do
			local resp = line.responses[r]
			if ( istable( resp ) ) then
				local rr = resp.searchRadius or line.searchRadius or MetroDialogue.GetDefaultSearchRadius()
				local nearby = MetroDialogue.GetNearbyMetropolice( responder, rr )
				local parts = { responder }
				for k = 1, #nearby do parts[#parts + 1] = nearby[k] end

				if ( MetroDialogue.IsGroupAllowed( resp.requiresGroup, 1 + #nearby )
					and MetroDialogue.IsAloneAllowed( resp.shouldBeAlone, #nearby )
					and MetroDialogue.EvaluateCanSay( resp.canSay, speaker, nearby, parts, line, resp )
					and MetroDialogue.IsScheduleAllowed( responder, resp.includeSchedules, resp.excludeSchedules ) ) then
					allowed[#allowed + 1] = resp
				end
			end
		end

		return allowed
	end

	-- Schedule a sequence of responder replies with gaps, minimizing nested closures
	function MetroDialogue.ScheduleResponses( order, line, speaker, participants, sessionId )
		local chainOffset = 0
		for i = 1, #order do
			local responder = order[i]
			local allowed = MetroDialogue.ComputeAllowedResponsesFor( responder, line, speaker )
			if ( allowed[1] != nil ) then
				local response = allowed[ math.random( #allowed ) ]
				local respDur = MetroDialogue.SafeSoundDuration( response.soundPath, response.text )
				local startDelay = chainOffset

				timer.Simple( startDelay, function()
					MetroDialogue.ResponderSpeak( responder, response, participants, respDur, sessionId )
				end)

				local gap = ( cvar_gap and cvar_gap:GetFloat() ) or ( MetroDialogue.ResponseGap or 0.15 )
				chainOffset = chainOffset + respDur + gap
			end
		end

		timer.Simple( chainOffset + 0.2, function()
			MetroDialogue.ClearDialoguePartners( participants, sessionId )
		end)
	end

	-- Helper to clear dialogue partners for a set of participants without nesting pyramids
	function MetroDialogue.ClearDialoguePartners( participants, sessionId )
		if ( !istable( participants ) ) then return end

		for i = 1, #participants do
			local p = participants[i]

			if ( IsValid( p ) ) then
				local t = p:GetTable()
				if ( !istable( t ) ) then return end

					-- Only clear if this is the same session
				if ( sessionId == nil or t.MetroDialogue_SessionId == sessionId ) then
					t.MetroDialogue_DialoguePartners = {}
				end
			end
		end
	end

	-- Group requirement helper: supports boolean (true means >=3) or numeric threshold
	function MetroDialogue.IsGroupAllowed( requiresGroup, participantCount )
		if ( requiresGroup == nil ) then return true end

		if ( isbool( requiresGroup ) ) then
			local minGroup = ( cvar_min_group and cvar_min_group:GetInt() ) or ( MetroDialogue.MinGroupSize or 3 )
			return ( requiresGroup == false ) or ( participantCount >= minGroup )
		end

		if ( isnumber( requiresGroup ) ) then
			return participantCount >= requiresGroup
		end

		return true
	end

	-- "Alone" requirement helper:
	--  - When shouldBeAlone == true, only allow if there are zero listeners.
	--  - When shouldBeAlone is nil/false and there are zero listeners, disallow (prevents accidental monologues).
	function MetroDialogue.IsAloneAllowed( shouldBeAlone, listenerCount )
		if ( isbool( shouldBeAlone ) and shouldBeAlone == true ) then
			return listenerCount == 0
		end

		if ( listenerCount == 0 ) then
			return false
		end

		return true
	end

	-- Returns responses that are eligible for the current participant count (and optional canSay checks)
	-- Evaluate canSay rules safely (function or boolean). If function, signature is (speaker, listeners, participants, line, response?)
	function MetroDialogue.EvaluateCanSay( rule, speaker, listeners, participants, line, response )
		if ( isfunction( rule ) ) then
			local ok, res = pcall( rule, speaker, listeners, participants, line, response )
			return ok and res == true
		elseif ( isbool( rule ) ) then
			return rule == true
		end

		return true
	end

	-- Check if speaker's current schedule matches include/exclude requirements
	function MetroDialogue.IsScheduleAllowed( npc, includeSchedules, excludeSchedules )
		if ( !IsValid( npc ) or !npc:IsNPC() ) then return true end

		-- If includeSchedules is specified, NPC must be running one of those schedules
		if ( istable( includeSchedules ) and includeSchedules[1] != nil ) then
			local matched = false
			for i = 1, #includeSchedules do
				if ( npc:IsCurrentSchedule( includeSchedules[i] ) ) then
					matched = true
					break
				end
			end

			if ( !matched ) then return false end
		end

		-- If excludeSchedules is specified, NPC must NOT be running any of those schedules
		if ( istable( excludeSchedules ) and excludeSchedules[1] != nil ) then
			for i = 1, #excludeSchedules do
				if ( npc:IsCurrentSchedule( excludeSchedules[i] ) ) then
					return false
				end
			end
		end

		return true
	end
	
	-- Helper to perform a listener's reply (reduces nesting inside timers)
	function MetroDialogue.ResponderSpeak( responder, response, participants, respDur, sessionId )
		if ( !IsValid( responder ) ) then return end
		local t = responder:GetTable()
		if ( !istable( t ) ) then return end

		-- Ensure still in the same session
		if ( sessionId != nil and t.MetroDialogue_SessionId != sessionId ) then return end

		t.MetroDialogue_SpeakingUntil = CurTime() + respDur + 0.1
		t.MetroDialogue_DialoguePartners = participants
		responder:EmitSound( response.soundPath or "", 75, 100, 1, CHAN_VOICE )
		MetroDialogue.Caption( responder, response.text or "" )
	end

	function MetroDialogue.Play( speaker, listeners )
		-- Pick a line that satisfies group requirements, optional shouldBeAlone, and optional canSay
		local allowedLines = {}
		for i = 1, #MetroDialogue.Lines do
			local line = MetroDialogue.Lines[i]

			if ( istable( line ) ) then
				local lr = line.searchRadius or MetroDialogue.GetDefaultSearchRadius()
				local effectiveListeners = MetroDialogue.GetNearbyMetropolice( speaker, lr )
				local effectiveParticipants = { speaker }
				for j = 1, #effectiveListeners do effectiveParticipants[#effectiveParticipants + 1] = effectiveListeners[j] end

				if ( MetroDialogue.IsGroupAllowed( line.requiresGroup, 1 + #effectiveListeners )
					and MetroDialogue.IsAloneAllowed( line.shouldBeAlone, #effectiveListeners )
					and MetroDialogue.EvaluateCanSay( line.canSay, speaker, effectiveListeners, effectiveParticipants, line )
					and MetroDialogue.IsScheduleAllowed( speaker, line.includeSchedules, line.excludeSchedules ) ) then
					allowedLines[#allowedLines + 1] = { line = line, listeners = effectiveListeners, participants = effectiveParticipants }
				end
			end
		end

		if ( allowedLines[1] == nil ) then return end

		local chosen = allowedLines[ math.random( #allowedLines ) ]
		local randomDialogue = table.Copy( chosen.line )
		if ( !istable( randomDialogue ) ) then return end

		-- Override listeners/participants to match the selected line's radius
		listeners = chosen.listeners or {}
		-- listeners/participants are now based on the selected line's radius; tmpParticipants not needed

		randomDialogue = hook.Run( "MetroDialogue_ModifyLine", speaker, listeners, randomDialogue ) or randomDialogue
		if ( !istable( randomDialogue ) ) then return end

		if ( !MetroDialogue.CanSpeak( speaker ) ) then return end

		local speakerTable = speaker:GetTable()
		local speakDur = MetroDialogue.SafeSoundDuration( randomDialogue.soundPath, randomDialogue.text )

		-- Mark all participants as engaged immediately
		local participants = { speaker }
		for i = 1, #listeners do participants[#participants + 1] = listeners[i] end

		-- Assign a session id to guard timers and cleanup
		local sessionId = string.format("md_%d_%d", math.floor( CurTime() * 1000 ), speaker:EntIndex() )

		for i = 1, #participants do
			local p = participants[i]
			local t = p:GetTable()

			if ( istable( t ) ) then
				t.MetroDialogue_SessionId = sessionId
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

		-- Zero-listener (monologue) path
		if ( listeners[1] == nil ) then
			-- Speaker already marked above; just play and clear after
			timer.Simple( speakDur + 0.2, function()
				MetroDialogue.ClearDialoguePartners( participants, sessionId )
			end)

			return
		end

		if ( listeners[ 2 ] != nil ) then
			timer.Simple( speakDur + 0.2, function()
				if ( !IsValid( speaker ) ) then return end

				-- If session changed, abort
				local st = speaker:GetTable()
				if ( !istable( st ) or st.MetroDialogue_SessionId != sessionId ) then return end

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


				-- Choose primary responder randomly, then optionally queue more based on chance
				local order = {}
				local primaryIndex = math.random( 1, #candidates )
				order[1] = candidates[ primaryIndex ]

				for i = 1, #candidates do
					if ( i == primaryIndex ) then continue end
					local chance = ( cvar_multi and cvar_multi:GetFloat() ) or ( MetroDialogue.MultiResponderChance or 0.5 )
					if ( math.Rand( 0, 1 ) < chance ) then
						order[ #order + 1 ] = candidates[ i ]
					end
				end

				-- Schedule responses sequentially via helper (reduces nesting)
				MetroDialogue.ScheduleResponses( order, randomDialogue, speaker, participants, sessionId )
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

			-- Abort if session changed
			local lt = speaker:GetTable()
			if ( !istable( lt ) or lt.MetroDialogue_SessionId != sessionId ) then return end

			-- Compute allowed responses for this single listener using helper
			local allowedResponses = MetroDialogue.ComputeAllowedResponsesFor( listener, randomDialogue, speaker )

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
				MetroDialogue.ClearDialoguePartners( participants, sessionId )
			end)
		end)

	end

	-- Client caption sender
	function MetroDialogue.Caption( speaker, sentence )
		net.Start( "MetroDialogue_Caption" )
			net.WriteEntity( speaker )
			net.WriteString( sentence )
			net.WriteColor( speaker:GetTable().MetroDialogue_DialogueColour or Color( 255, 255, 255 ) )
		net.SendPAS( speaker:GetPos() )
	end

	hook.Add( "OnEntityCreated", "MetroDialogue_NPCInit", function( ent )
		if ( !IsValid( ent ) or !ent:IsNPC() ) then return end
		if ( ent:GetClass() != "npc_metropolice" ) then return end

		local entTable = ent:GetTable()
		if ( !istable( entTable ) ) then return end

		entTable.MetroDialogue_SpeakingUntil = 0
		entTable.MetroDialogue_DialoguePartners = {}
		entTable.MetroDialogue_DialogueColour = Color( math.random( 0, 255 ), math.random( 0, 255 ), math.random( 0, 255 ) )

		print( "[ MetroDialogue ] Initialised NPC: " .. tostring( ent ) )

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

	local metrocops = ents.FindByClass( "npc_metropolice" )
	for i = 1, #metrocops do
		local cop = metrocops[ i ]

		local timerID = "MetroDialogue_NPCInit_" .. cop:EntIndex()
		if ( timer.Exists( timerID ) ) then
			timer.Remove( timerID )
			MetroDialogue.InitialiseTimer( cop )
		end
	end
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
end
