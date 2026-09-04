-- Author: @iGottic (Mia Gobble)
-- See more info here: https://github.com/MiaGobble/Praxis

local Praxis = {}

-- Imports
local Packages = script:FindFirstChild("roblox_packages")
	or script:FindFirstChild("Packages")
	or script.Parent

Praxis.Bucket = require(Packages.Bucket)
Praxis.Symbol = require(Packages.Symbol)
Praxis.Typer = require(Packages.Typer)
Praxis.TracebackUtils = require(Packages.TracebackUtils)
Praxis.SeamStoryUttils = require(Packages.SeamStoryUtils)
Praxis.ProgressionUtils = require(Packages.ProgressionUtils)
Praxis.Initializer = require(Packages.Initializer)
Praxis.Signal = require(Packages.Signal)
Praxis.DialogueTree = require(Packages.DialogueTree)
Praxis.TagUtils = require(Packages.TagUtils)
Praxis.Bezier = require(Packages.Bezier)
Praxis.ValuePacker = require(Packages.ValuePacker)
Praxis.Oklab = require(Packages.Oklab)
Praxis.EffectPlayer = require(Packages.EffectPlayer)
Praxis.Child = require(Packages.Child)
Praxis.Optional = require(Packages.Optional)
Praxis.Badges = require(Packages.Badges)
Praxis.SerDes = require(Packages.SerDes)
Praxis.DataStore = require(Packages.DataStore)
Praxis.Input = require(Packages.Input)
Praxis.RateLimiter = require(Packages.RateLimiter)
Praxis.Time = require(Packages.Time)
Praxis.Binder = require(Packages.Binder)
Praxis.Replicator = require(Packages.Replicator)

return Praxis
