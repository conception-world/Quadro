--!strict
local theme = {}

-- AVISO: valores em lockstep com Yeet/yeet-plugin/src/ui/theme.luau; mudar um exige mudar o outro.
theme.colors = {
	background = Color3.fromRGB(18, 18, 22),
	card = Color3.fromRGB(30, 30, 36),
	surface = Color3.fromRGB(44, 44, 52),
	surfaceActive = Color3.fromRGB(60, 60, 70),
	stroke = Color3.fromRGB(52, 52, 60),
	text = Color3.fromRGB(240, 240, 245),
	textMuted = Color3.fromRGB(150, 150, 162),
	textInverse = Color3.fromRGB(22, 22, 28),
	accentPrimary = Color3.fromRGB(100, 130, 240),
	accentAccept = Color3.fromRGB(60, 200, 130),
	accentDecline = Color3.fromRGB(230, 80, 100),
	accentWarning = Color3.fromRGB(235, 180, 70),
	accentInfo = Color3.fromRGB(100, 170, 230),
	gradientBase = Color3.new(1, 1, 1),
	shade = Color3.new(0, 0, 0),
}

theme.radius = {
	sm = 6,
	md = 10,
	lg = 16,
	pill = 999,
}

theme.spacing = {
	tight = 4,
	sm = 8,
	md = 12,
	lg = 16,
	xl = 24,
}

theme.sizes = {
	toggleWidth = 36,
	toggleHeight = 20,
	toggleKnob = 14,
	swatchWidth = 112,
	swatchHeight = 44,
	swatchLabel = 34,
	anchorCell = 30,
	row = 32,
	keyWidth = 112,
	keyHeight = 26,
	anchorToggleHeight = 64,
	emptyStateHeight = 40,
	toggleRowTall = 60,
	toggleKnobInset = 3,
	toggleTrackGap = 2,
	toggleTitleExtra = 3,
	anchorDot = 6,
	anchorDotInset = 6,
	toastHeight = 28,
	toastDot = 8,
	badgeHeight = 22,
	selectWidth = 84,
	listMaxHeight = 220,
	scrollBar = 4,
	tabScrollBar = 3,
	tabBarGap = 2,
	tabStripInset = 2,
	tabWheelStep = 48,
	gradientStrip = 28,
	stopTrack = 24,
	stopMarker = 12,
	stopMarkerActive = 16,
	fieldWidth = 48,
	hexFieldWidth = 80,
	nameFieldWidth = 140,
	fieldHeight = 28,
	chip = 20,
	chipStroke = 1,
	markerStroke = 1.5,
	markerStrokeActive = 2,
	trackLine = 2,
	slicePreviewWidth = 200,
	slicePreviewHeight = 64,
	pickerWheel = 180,
	pickerSlider = 12,
	pickerMarker = 12,
	pickerSwatch = 24,
}

theme.typography = {
	title = { font = Enum.Font.GothamBold, size = 16 },
	subtitle = { font = Enum.Font.GothamMedium, size = 13 },
	body = { font = Enum.Font.Gotham, size = 13 },
	label = { font = Enum.Font.GothamMedium, size = 12 },
	caption = { font = Enum.Font.Gotham, size = 11 },
}

return theme
