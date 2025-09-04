MsgC( Color( 190, 255, 255 ), "[ MetroDialogue ] Loading...!\n" )

MetroDialogue = MetroDialogue or {}

if ( SERVER ) then
    util.AddNetworkString( "MetroDialogue_Caption" )
else
    net.Receive( "MetroDialogue_Caption", function()
        local npc = net.ReadEntity()
        if ( !IsValid(npc) ) then return end
        if ( npc:IsDormant() or !LocalPlayer():IsLineOfSightClear(npc) ) then return end
        if ( npc:GetPos():DistToSqr( LocalPlayer():GetPos() ) > 350 ^ 2 ) then return end

        local text = net.ReadString()
        if ( !isstring( text ) or #text == 0 ) then return end

        local captionDuration = #text * 0.1
        local colour = net.ReadColor()

        text = "<clr:" .. colour.r .. "," .. colour.g .. "," .. colour.b .. ">" .. text

        gui.AddCaption( text, captionDuration )
    end)
end

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
        questionSoundPath = "metrodialogue/h6bridge.wav",
        questionText = "Hey, did you hear about about HERO-6 ? I believe he jumped off a bridge.",

        responses = {
            { soundPath = "metrodialogue/precintlostmind.wav", text = "Bloody hell, even the precinct is losing it's mind." }
        }
    },
    {
        questionSoundPath = "metrodialogue/imaginebeingcitizen.wav",
        questionText = "Imagine still being a citizen.",

        responses = {
            { soundPath = "metrodialogue/mhm.wav", text = "<i>Mhm.</i>" }
        }
    },
    {
        questionSoundPath = "metrodialogue/bestcareerchoice.wav",
        questionText = "THIS was definitely the best career choice, I've ever made.",

        responses = {
            { soundPath = "metrodialogue/tellmeaboutit.wav", text = "Tell me about it." }
        }
    },
}

if ( SERVER ) then
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

    function MetroDialogue.Caption( speaker, questionText, colour )
        net.Start( "MetroDialogue_Caption" )
            net.WriteEntity( speaker )
            net.WriteString( questionText )
            net.WriteColor( colour or Color( 255, 255, 255 ) )
        net.SendPVS( speaker:GetPos() )
    end

    hook.Add( "MetroDialogue_ShouldPlay", "MetroDialogue_ShouldPlay", function( npc, npc2 )
        local t1, t2 = npc:GetTable(), npc2:GetTable()
        if ( !istable( t1 ) or !istable( t2 ) ) then return false end
        if ( !npc:IsCurrentSchedule( SCHED_IDLE_STAND ) ) then return false end
        if ( npc:GetPos():DistToSqr( npc2:GetPos() ) > 192 ^ 2 ) then return false end
        if ( IsValid( t1.DialoguePartner ) or IsValid( t2.DialoguePartner ) ) then return false end
        if ( MetroDialogue.IsSpeaking( npc ) or MetroDialogue.IsSpeaking( npc2 ) ) then return false end

        return true
    end )

    hook.Add( "OnEntityCreated", "MetroDialogue_NPCInit", function( ent )
        if ( !IsValid( ent ) or !ent:IsNPC() ) then return end
        if ( ent:GetClass() != "npc_metropolice" ) then return end

        local entTable = ent:GetTable()
        if ( !istable( entTable ) ) then return end

        entTable.Metro_SpeakingUntil = 0
        entTable.DialoguePartner = NULL
        entTable.DialogueColour = Color( math.random( 0, 255 ), math.random( 0, 255 ), math.random( 0, 255 ) )

        local timerID = "MetroDialogue_NPCInit_" .. ent:EntIndex()
        timer.Create( timerID, 5, 0, function()
            if ( !IsValid( ent ) ) then return end
            local entTable = ent:GetTable()
            if ( !istable( entTable ) ) then return end



            timer.Remove( timerID )
        end )
    end )
end
