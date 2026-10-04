--!strict
-- HUD CONTROLLER
-- Everything drawn on screen, built in code:
--   * bottom-centre: the shot timing meter, the shot type and the result callout
--   * top-right: a stats panel (speed, distance to the rim, field goals) for tuning
-- ShotController tells it what to show through beginShot / setProgress / releaseShot /
-- shotResolved.

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

-- COLOURS (red, green, blue from 0 to 255) --------------------------------------------

local TEXT_COLOR = Color3.fromRGB(240, 240, 240)
local PANEL_COLOR = Color3.fromRGB(16, 18, 22) -- dark background behind the meter and stats
local FILL_COLOR = Color3.fromRGB(235, 235, 235) -- meter fill while E is held
local MADE_COLOR = Color3.fromRGB(80, 220, 120) -- "BUCKET" text
local MISSED_COLOR = Color3.fromRGB(235, 80, 80) -- "MISS" text

-- Meter fill and callout colour for each release grade.
local GRADE_COLORS: { [ShotMath.Grade]: Color3 } = {
	Perfect = Color3.fromRGB(80, 220, 120), -- green (also the green zone's colour)
	Good = Color3.fromRGB(240, 210, 80), -- yellow
	Early = Color3.fromRGB(245, 150, 60), -- orange
	Late = Color3.fromRGB(245, 150, 60),
	VeryEarly = Color3.fromRGB(235, 80, 80), -- red
	VeryLate = Color3.fromRGB(235, 80, 80),
}

-- Callout text for each release grade.
local GRADE_TEXT: { [ShotMath.Grade]: string } = {
	Perfect = "PERFECT",
	Good = "GOOD",
	Early = "EARLY",
	Late = "LATE",
	VeryEarly = "WAY EARLY",
	VeryLate = "WAY LATE",
}

-- FADING ------------------------------------------------------------------------------

local FADE_DELAY = 1.3 -- seconds the result stays on screen before fading
local FADE_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- fade length and curve

-- SCREEN ELEMENTS (created in build()) --------------------------------------------------

local shotGroup: CanvasGroup -- holds the meter and callouts so they fade together
local meterFill: Frame -- the bar that grows while E is held
local perfectZone: Frame -- the green zone
local targetTick: Frame -- the white line at the perfect moment
local shotLabel: TextLabel -- shot type, e.g. "JUMP SHOT"
local resultLabel: TextLabel -- grade and result, e.g. "PERFECT · BUCKET"
local statsLabel: TextLabel -- text inside the stats panel

-- STATE -------------------------------------------------------------------------------

local makes, attempts = 0, 0 -- field goals this session
-- Increased to cancel a pending fade-out; a scheduled fade only runs if it hasn't changed.
local fadeToken = 0
local fadeTween: Tween? = nil -- the fade currently playing, if any

-- Creates a transparent-background text label with the shared style.
local function makeLabel(parent: Instance, name: string, textSize: number, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextColor3 = TEXT_COLOR
	label.TextSize = textSize
	label.Font = font
	label.TextStrokeTransparency = 0.6 -- faint outline so text reads on any background
	label.Parent = parent
	return label
end

-- Rounds the corners of a frame by `radius` pixels.
local function corner(parent: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = parent
end

-- Converts shot progress into a position along the meter (0 = left end, 1 = right end).
-- The bar spans progress 0 to 1 + LATE_LIMIT, the point where the shot auto-releases.
local function meterScale(progress: number): number
	return math.clamp(progress / (1 + Shooting.LATE_LIMIT), 0, 1)
end

-- Creates every on-screen element once, when the game starts.
-- (UDim2 positions are "scale, pixels" pairs: scale 0.5 = halfway across the screen.)
local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoHoopsHud"
	gui.ResetOnSpawn = false -- keep the HUD (and the FG count) across respawns
	gui.IgnoreGuiInset = true -- position from the true top of the screen
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Shot area, bottom-centre. Starts invisible (GroupTransparency 1) until a shot begins.
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

	-- The meter's dark track.
	local meter = Instance.new("Frame")
	meter.Name = "Meter"
	meter.AnchorPoint = Vector2.new(0.5, 0)
	meter.Position = UDim2.new(0.5, 0, 0, 64)
	meter.Size = UDim2.fromOffset(260, 12) -- 260 × 12 pixels
	meter.BackgroundColor3 = PANEL_COLOR
	meter.BackgroundTransparency = 0.25
	meter.BorderSizePixel = 0
	meter.ClipsDescendants = true
	meter.Parent = shotGroup
	corner(meter, 6)

	-- Green zone. Its position and width are set in beginShot from the Shooting config.
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
	targetTick.Size = UDim2.new(0, 2, 1, 0) -- 2 pixels wide, full meter height
	targetTick.ZIndex = 2 -- drawn above the fill
	targetTick.Parent = meter

	-- Stats panel, top-right, clear of the chat window and Roblox's top-left menu buttons.
	local statsPanel = Instance.new("Frame")
	statsPanel.Name = "Stats"
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

	statsLabel = makeLabel(statsPanel, "Text", 14, Enum.Font.RobotoMono) -- monospace keeps numbers aligned
	statsLabel.Size = UDim2.fromScale(1, 1)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.TextYAlignment = Enum.TextYAlignment.Top
	statsLabel.TextStrokeTransparency = 1

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Stops any pending or playing fade-out.
local function cancelFade()
	fadeToken += 1
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
end

-- Fades the shot area out after FADE_DELAY seconds, unless a new shot starts first.
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

-- Runs every frame: refreshes the stats panel text.
local function updateStats()
	local parts = CharacterRef.get()
	local rimFeet = 0 -- flat distance from the player to the rim, in feet
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

-- E pressed: show an empty meter with the green zone, and the shot type.
function HudController.beginShot(label: string)
	cancelFade()
	shotGroup.GroupTransparency = 0

	-- Recalculated every shot so live-tuned timing values show up immediately.
	local ideal = Shooting.IDEAL_RELEASE
	local zoneStart = meterScale(ideal - Shooting.PERFECT_WINDOW)
	perfectZone.Position = UDim2.fromScale(zoneStart, 0)
	perfectZone.Size = UDim2.fromScale(meterScale(ideal + Shooting.PERFECT_WINDOW) - zoneStart, 1)
	targetTick.Position = UDim2.fromScale(meterScale(ideal), 0)

	meterFill.Size = UDim2.fromScale(0, 1)
	meterFill.BackgroundColor3 = FILL_COLOR
	shotLabel.Text = string.upper(label)
	resultLabel.Text = ""
end

-- E still held: grow the fill to the current progress.
function HudController.setProgress(progress: number)
	meterFill.Size = UDim2.fromScale(meterScale(progress), 1)
end

-- E released: freeze the fill and colour it (and the callout) by the grade.
function HudController.releaseShot(grade: ShotMath.Grade, progress: number)
	HudController.setProgress(progress)
	meterFill.BackgroundColor3 = GRADE_COLORS[grade]
	resultLabel.Text = GRADE_TEXT[grade]
	resultLabel.TextColor3 = GRADE_COLORS[grade]
end

-- Shot decided: update FG, show "GRADE · BUCKET/MISS", then fade out.
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
