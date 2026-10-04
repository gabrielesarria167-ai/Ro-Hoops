--!strict
-- Prototype HUD: the shot timing meter, the shot and result callouts, and a telemetry
-- readout (speed, distance to the rim, field goals) for tuning movement and shooting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Court = require(ReplicatedStorage.Shared.Config.Court)
local Shooting = require(ReplicatedStorage.Shared.Config.Shooting)
local ShotMath = require(ReplicatedStorage.Shared.ShotMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local MovementController = require(script.Parent.MovementController)

local HudController = {}

local TEXT_COLOR = Color3.fromRGB(240, 240, 240)
local PANEL_COLOR = Color3.fromRGB(16, 18, 22)
local FILL_COLOR = Color3.fromRGB(235, 235, 235)
local MADE_COLOR = Color3.fromRGB(80, 220, 120)
local MISSED_COLOR = Color3.fromRGB(235, 80, 80)

local GRADE_COLORS: { [ShotMath.Grade]: Color3 } = {
	Perfect = Color3.fromRGB(80, 220, 120),
	Good = Color3.fromRGB(240, 210, 80),
	Early = Color3.fromRGB(245, 150, 60),
	Late = Color3.fromRGB(245, 150, 60),
	VeryEarly = Color3.fromRGB(235, 80, 80),
	VeryLate = Color3.fromRGB(235, 80, 80),
}

local GRADE_TEXT: { [ShotMath.Grade]: string } = {
	Perfect = "PERFECT",
	Good = "GOOD",
	Early = "EARLY",
	Late = "LATE",
	VeryEarly = "WAY EARLY",
	VeryLate = "WAY LATE",
}

local FADE_DELAY = 1.3
local FADE_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local shotGroup: CanvasGroup
local meterFill: Frame
local perfectZone: Frame
local targetTick: Frame
local shotLabel: TextLabel
local resultLabel: TextLabel
local statsLabel: TextLabel

local makes, attempts = 0, 0
local fadeToken = 0
local fadeTween: Tween? = nil

local function makeLabel(parent: Instance, name: string, textSize: number, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextColor3 = TEXT_COLOR
	label.TextSize = textSize
	label.Font = font
	label.TextStrokeTransparency = 0.6
	label.Parent = parent
	return label
end

local function corner(parent: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = parent
end

-- Meter positions are fractions of the full bar, which spans progress 0 → 1 + LATE_LIMIT.
local function meterScale(progress: number): number
	return math.clamp(progress / (1 + Shooting.LATE_LIMIT), 0, 1)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoHoopsHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	shotGroup = Instance.new("CanvasGroup")
	shotGroup.Name = "Shot"
	shotGroup.AnchorPoint = Vector2.new(0.5, 1)
	shotGroup.Position = UDim2.new(0.5, 0, 1, -70)
	shotGroup.Size = UDim2.fromOffset(320, 96)
	shotGroup.BackgroundTransparency = 1
	shotGroup.GroupTransparency = 1
	shotGroup.Parent = gui

	resultLabel = makeLabel(shotGroup, "Result", 26, Enum.Font.GothamBlack)
	resultLabel.Size = UDim2.new(1, 0, 0, 30)

	shotLabel = makeLabel(shotGroup, "ShotType", 14, Enum.Font.GothamBold)
	shotLabel.Position = UDim2.fromOffset(0, 38)
	shotLabel.Size = UDim2.new(1, 0, 0, 18)
	shotLabel.TextTransparency = 0.2

	local meter = Instance.new("Frame")
	meter.Name = "Meter"
	meter.AnchorPoint = Vector2.new(0.5, 0)
	meter.Position = UDim2.new(0.5, 0, 0, 64)
	meter.Size = UDim2.fromOffset(260, 12)
	meter.BackgroundColor3 = PANEL_COLOR
	meter.BackgroundTransparency = 0.25
	meter.BorderSizePixel = 0
	meter.ClipsDescendants = true
	meter.Parent = shotGroup
	corner(meter, 6)

	perfectZone = Instance.new("Frame")
	perfectZone.Name = "PerfectZone"
	perfectZone.BackgroundColor3 = GRADE_COLORS.Perfect
	perfectZone.BackgroundTransparency = 0.55
	perfectZone.BorderSizePixel = 0
	perfectZone.Parent = meter

	meterFill = Instance.new("Frame")
	meterFill.Name = "Fill"
	meterFill.BackgroundColor3 = FILL_COLOR
	meterFill.BorderSizePixel = 0
	meterFill.Size = UDim2.fromScale(0, 1)
	meterFill.Parent = meter

	targetTick = Instance.new("Frame")
	targetTick.Name = "Target"
	targetTick.AnchorPoint = Vector2.new(0.5, 0)
	targetTick.BackgroundColor3 = TEXT_COLOR
	targetTick.BorderSizePixel = 0
	targetTick.Size = UDim2.new(0, 2, 1, 0)
	targetTick.ZIndex = 2
	targetTick.Parent = meter

	local statsPanel = Instance.new("Frame")
	statsPanel.Name = "Stats"
	-- Top-right, clear of the chat window and Roblox's top-left menu buttons.
	statsPanel.AnchorPoint = Vector2.new(1, 0)
	statsPanel.Position = UDim2.new(1, -16, 0, 64)
	statsPanel.Size = UDim2.fromOffset(170, 74)
	statsPanel.BackgroundColor3 = PANEL_COLOR
	statsPanel.BackgroundTransparency = 0.35
	statsPanel.BorderSizePixel = 0
	statsPanel.Parent = gui
	corner(statsPanel, 8)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 8)
	padding.Parent = statsPanel

	statsLabel = makeLabel(statsPanel, "Text", 14, Enum.Font.RobotoMono)
	statsLabel.Size = UDim2.fromScale(1, 1)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.TextYAlignment = Enum.TextYAlignment.Top
	statsLabel.TextStrokeTransparency = 1

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function cancelFade()
	fadeToken += 1
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
end

local function fadeOutLater()
	cancelFade()
	local token = fadeToken
	task.delay(FADE_DELAY, function()
		if token ~= fadeToken then
			return
		end
		local tween = TweenService:Create(shotGroup, FADE_INFO, { GroupTransparency = 1 })
		fadeTween = tween
		tween:Play()
	end)
end

local function updateStats()
	local parts = CharacterRef.get()
	local rimFeet = 0
	if parts then
		local offset = Court.RIM_POSITION - parts.root.Position
		rimFeet = Vector3.new(offset.X, 0, offset.Z).Magnitude / Court.STUDS_PER_FOOT
	end
	local percent = if attempts > 0 then math.floor(makes / attempts * 100 + 0.5) else 0
	statsLabel.Text = string.format(
		"SPEED %5.1f\nRIM   %5.1f ft\nFG    %d/%d (%d%%)",
		MovementController.getVelocity().Magnitude,
		rimFeet,
		makes,
		attempts,
		percent
	)
end

function HudController.beginShot(label: string)
	cancelFade()
	shotGroup.GroupTransparency = 0

	-- Laid out on every shot so live-tuned windows show up immediately.
	local zoneStart = meterScale(1 - Shooting.PERFECT_WINDOW)
	perfectZone.Position = UDim2.fromScale(zoneStart, 0)
	perfectZone.Size = UDim2.fromScale(meterScale(1 + Shooting.PERFECT_WINDOW) - zoneStart, 1)
	targetTick.Position = UDim2.fromScale(meterScale(1), 0)

	meterFill.Size = UDim2.fromScale(0, 1)
	meterFill.BackgroundColor3 = FILL_COLOR
	shotLabel.Text = string.upper(label)
	resultLabel.Text = ""
end

function HudController.setProgress(progress: number)
	meterFill.Size = UDim2.fromScale(meterScale(progress), 1)
end

function HudController.releaseShot(grade: ShotMath.Grade, progress: number)
	HudController.setProgress(progress)
	meterFill.BackgroundColor3 = GRADE_COLORS[grade]
	resultLabel.Text = GRADE_TEXT[grade]
	resultLabel.TextColor3 = GRADE_COLORS[grade]
end

function HudController.shotResolved(made: boolean, grade: ShotMath.Grade)
	attempts += 1
	if made then
		makes += 1
	end
	cancelFade()
	shotGroup.GroupTransparency = 0
	resultLabel.Text = string.format("%s · %s", GRADE_TEXT[grade], if made then "BUCKET" else "MISS")
	resultLabel.TextColor3 = if made then MADE_COLOR else MISSED_COLOR
	fadeOutLater()
end

function HudController.start()
	build()
	RunService.RenderStepped:Connect(updateStats)
end

return HudController
