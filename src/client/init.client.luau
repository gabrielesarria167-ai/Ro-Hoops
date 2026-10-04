--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tunable = require(ReplicatedStorage.Shared.Tunable)
local CharacterRef = require(script.CharacterRef)
local Controllers = script.Controllers
local BallController = require(Controllers.BallController)
local CameraController = require(Controllers.CameraController)
local HudController = require(Controllers.HudController)
local InputController = require(Controllers.InputController)
local MovementController = require(Controllers.MovementController)
local ShotController = require(Controllers.ShotController)

local Config = ReplicatedStorage.Shared.Config
Tunable.bind("Movement", require(Config.Movement))
Tunable.bind("Camera", require(Config.Camera))
Tunable.bind("Shooting", require(Config.Shooting))
Tunable.bind("Ball", require(Config.Ball))

CharacterRef.start()
InputController.start()
MovementController.start()
CameraController.start()
BallController.start()
HudController.start()
ShotController.start()
