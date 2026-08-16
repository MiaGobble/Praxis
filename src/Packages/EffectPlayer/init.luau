--[=[
    @class EffectPlayer

    Allows you to play visual effects created by standard visual effect plugins. This supports playing:
    * ParticleEmitters
    * Sounds
    * Tween and bezier animations
    * ModuleScripts
    * Beams
    * Trails
]=]

local EffectPlayer = {}

-- Services
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Imports
local Bezier = require("@pkg/Bezier")

type AnimationIndicator = Instance & {
	Duration: NumberValue,
	TweenStyle: StringValue,
	TweenDirection: StringValue,
	RepeatCount: NumberValue,
	Reverses: BoolValue,
	DelayTime: NumberValue,
}

type CFrameInstance = BasePart | Attachment | Camera

-- Variables
local ActiveTasks = {}

-- Get time from tween info
local function GetTimeFromTweenInfo(TweenInfo : TweenInfo): number
    local Duration = TweenInfo.Time
    local Delay = TweenInfo.DelayTime

    if TweenInfo.Reverses then
        Duration *= 2
    end
    
    if TweenInfo.RepeatCount > 0 then
        Duration *= (TweenInfo.RepeatCount + 1)
    end

    return Duration + Delay
end

-- Helper function to calculate distance-based volume
local function CalculateVolume(Sound: Sound, ParentInstance: BasePart | Attachment): number
    -- Return 1 if not using plugin
    if RunService:IsRunning() then
        return 1
    end

    local Camera = workspace.CurrentCamera
    if not Camera then return 1 end
    
    local ParentPosition = if ParentInstance:IsA("Attachment") 
        then ParentInstance.WorldPosition 
        else ParentInstance.Position
    
    local Distance = (ParentPosition - Camera.CFrame.Position).Magnitude
    
    -- Get rolloff properties from sound
    local MinDistance = Sound.RollOffMinDistance
    local MaxDistance = Sound.RollOffMaxDistance
    local RolloffMode = Sound.RollOffMode

    -- Calculate volume based on distance and rolloff mode
    if Distance <= MinDistance then
        return 1
    elseif Distance >= MaxDistance then
        return 0
    end
    
    local Volume
    
    if RolloffMode == Enum.RollOffMode.Linear then
        Volume = 1 - ((Distance - MinDistance) / (MaxDistance - MinDistance))
    elseif RolloffMode == Enum.RollOffMode.Inverse then
        Volume = math.clamp(MinDistance / math.max(Distance, MinDistance), 0, 1)
    else -- Default to linear
        local Alpha = (Distance - MinDistance) / (MaxDistance - MinDistance)
        Volume = 1 - math.clamp(Alpha * Alpha, 0, 1)
    end
    
    return Volume
end

local function TweenInfoFromAnimationIndicator(animationIndicator: AnimationIndicator): (TweenInfo)
	return TweenInfo.new(
        animationIndicator.Duration.Value,
        Enum.EasingStyle:FromName(animationIndicator.TweenStyle.Value),
        Enum.EasingDirection:FromName(animationIndicator.TweenDirection.Value),
        animationIndicator.RepeatCount.Value,
        animationIndicator.Reverses.Value,
        animationIndicator.DelayTime.Value
    )
end

-- Function to animate tweens
local function AnimateTween(ParentAttachment : Attachment): (number?)
    local Mover = ParentAttachment:FindFirstChild("Mover") :: CFrameInstance?

    if not Mover then
        return nil
    end

    local Origin = ParentAttachment:FindFirstChild("Origin") :: CFrameInstance?

    if not Origin then
        return nil
    end

    local Target = ParentAttachment:FindFirstChild("Target") :: CFrameInstance?

    if not Target then
        return nil
    end
    
    local AnimationIndicator = ParentAttachment:FindFirstChild("AnimationIndicator") :: AnimationIndicator?

    if not AnimationIndicator then
        return nil
    end

    local TweenStyle = TweenInfoFromAnimationIndicator(AnimationIndicator)

    local Tween = TweenService:Create(Mover, TweenStyle, {
        CFrame = Target.CFrame
    })

    Mover.CFrame = Origin.CFrame
    Tween:Play()

    return GetTimeFromTweenInfo(TweenStyle)
end

-- Function to animate bezier tweens
local function AnimateBezier(ParentAttachment : Attachment): (number?)
    local Mover = ParentAttachment:FindFirstChild("Mover") :: CFrameInstance?

    if not Mover then
        return nil
    end

    local Origin = ParentAttachment:FindFirstChild("Origin") :: CFrameInstance?

    if not Origin then
        return nil
    end
    
    local Target = ParentAttachment:FindFirstChild("Target") :: CFrameInstance?

    if not Target then
        return nil
    end

    local Midpoints: {Attachment?} = {ParentAttachment:FindFirstChild("Midpoint") :: Attachment?}

    for _, Midpoint in ParentAttachment:GetChildren() do
        if not Midpoint:IsA("Attachment") then
            continue
        end

        local MidpointIndex = tonumber(Midpoint.Name:gsub("Midpoint", ""))

        if MidpointIndex then
            Midpoints[MidpointIndex] = Midpoint
        end
    end

    local AnimationIndicator = ParentAttachment:FindFirstChild("AnimationIndicator") :: AnimationIndicator?

    if not AnimationIndicator then
        return nil
    end

    local Positions = {}

    table.insert(Positions, Origin.WorldPosition)

    for _, Midpoint in Midpoints do
        table.insert(Positions, Midpoint.WorldPosition)
    end

    table.insert(Positions, Target.WorldPosition)

    local TweenStyle = TweenInfoFromAnimationIndicator(AnimationIndicator)

	local OldReferenceValue = Mover:FindFirstChild("ReferenceValue")
    if OldReferenceValue then
       OldReferenceValue:Destroy()
    end

    local ReferenceValue = Instance.new("NumberValue")
    ReferenceValue.Value = 0
    ReferenceValue.Name = "ReferenceValue"
    ReferenceValue.Parent = Mover

    local Tween = TweenService:Create(ReferenceValue, TweenStyle, {
        Value = 1
    })

    Tween.Completed:Connect(function()
        ReferenceValue:Destroy()
    end)

    ReferenceValue.Changed:Connect(function()
        local Position = Bezier.Evaluate(Positions, ReferenceValue.Value)
        Mover.WorldPosition = Position
    end)

    --Debris:AddItem(ReferenceValue, GetTimeFromTweenInfo(TweenStyle))
    Mover.CFrame = Origin.CFrame
    Tween:Play()

    return GetTimeFromTweenInfo(TweenStyle)
end

-- Actually plays the effect
local function PlayEffect(This : Instance, Bin : Instance) : number?
    local TotalDuration = nil
	local EmitDelay = This:GetAttribute(`"EmitDelay"`) :: number? or 0
	local EmitDuration = This:GetAttribute("EmitDuration") :: number? or 0

    if This:IsA("ModuleScript") then
        local Duplicate = This:Clone()
        Duplicate.Parent = script

        local Module: {Identifier: any, Callback: any, Cleanup: any, Lifetime: any} = require(Duplicate) :: any

        if typeof(Module) ~= "table" then
            return nil
        end

        if not Module.Identifier or Module.Identifier ~= "VISUAL_EFFECT" then
            return nil
        end

        if not Module.Callback then
            warn(`No callback found in {This:GetFullName()}`)
            return nil
        end

        if not Module.Cleanup then
            warn(`No cleanup found in {This:GetFullName()}`)
            return nil
        end

        if not Module.Lifetime then
            warn(`No lifetime found in {This:GetFullName()}`)
            return nil
        end
        
        task.delay(EmitDelay, function()
            (Module.Callback :: any)(This.Parent)

            task.delay(Module.Lifetime, function()
                local Success, Error = pcall(function()
                    (Module.Cleanup :: any)(This.Parent)
                end)

                if not Success then
                    warn(Error)
                end

                Duplicate:Destroy()
            end)
        end)

        TotalDuration = Module.Lifetime + EmitDelay
    elseif This:IsA("ParticleEmitter") then
        task.delay(EmitDelay, function()
            This:Emit(This:GetAttribute("EmitCount") :: number? or 1)

            if EmitDuration > 0 then
                This.Enabled = true

                task.delay(EmitDuration, function()
                    This.Enabled = false
                end)
            end
        end)

        TotalDuration = EmitDuration + EmitDelay + This.Lifetime.Max
    elseif This:IsA("Sound") then
        local NewSound = This:Clone()
        NewSound.Parent = This.Parent or workspace

        task.delay(EmitDelay, function()
            -- Set initial volume based on distance
            if This.Parent and (This.Parent:IsA("BasePart") or This.Parent:IsA("Attachment")) then
                local Attenuation = CalculateVolume(This, This.Parent)
                NewSound.Volume *= Attenuation
            end
            
            if RunService:IsRunning() then
                NewSound:Play()
            else
                task.defer(function()
                    NewSound:Play()
                end)
            end

            if EmitDuration > 0 then
                task.delay(EmitDuration, function()
                    NewSound:Stop()
                end)
            end

            NewSound.Ended:Connect(function()
                NewSound:Destroy()
            end)
        end)

        if EmitDuration > 0 then
            TotalDuration = EmitDuration + EmitDelay
        else
            TotalDuration = (This.TimeLength / This.PlaybackSpeed) + EmitDelay
        end
    elseif This:IsA("Trail") then
        This.Enabled = false

        table.insert(ActiveTasks[Bin], task.delay(EmitDelay, function()
            This.Enabled = true

            table.insert(ActiveTasks[Bin], task.delay(EmitDuration, function()
                This.Enabled = false
            end))
        end))

        TotalDuration = EmitDuration + EmitDelay
    elseif This:IsA("StringValue") and This.Name == "AnimationIndicator" then
        if This.Value == "Tween" then
            TotalDuration = AnimateTween(This.Parent :: Attachment)
        elseif This.Value == "Bezier" then
            TotalDuration = AnimateBezier(This.Parent :: Attachment)
        end
    end

    return TotalDuration
end

--[=[
    @param Bin Instance -- The bin of effect objects or a single effect object to play.
    @param IgnoreAllDescendants boolean? -- If true, will not play effects on descendants of the bin. Defaults to false.
    @return number -- The total duration of the effect as a number.

    Plays a visual effect, returning the total duration of the effect as a number.
]=]

function EffectPlayer.PlayEffect(Bin : Instance, IgnoreAllDescendants : boolean?) : number
    if ActiveTasks[Bin] then
        for _, Task in ActiveTasks[Bin] do
            task.cancel(Task)
        end
    end

    ActiveTasks[Bin] = {}

    local MaxTime = PlayEffect(Bin, Bin)
    MaxTime = MaxTime or 0

    if not IgnoreAllDescendants then
        for _, This : Instance in Bin:GetDescendants() do
            if not This:IsDescendantOf(workspace) then
                continue
            end
    
            local Duration = PlayEffect(This, Bin)
    
            Duration = Duration or 0
            MaxTime = math.max(MaxTime, Duration)
        end
    end

    table.insert(ActiveTasks[Bin], task.delay(MaxTime, function()
        ActiveTasks[Bin] = nil
    end))

    return MaxTime
end

return EffectPlayer