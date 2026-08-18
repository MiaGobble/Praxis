--[=[
	@class Bezier

	A utility module for working with Bezier curves.
]=]

local Bezier = {}

-- Imports
local ValuePacker = require("@pkg/ValuePacker")

local function LerpComponentValues(StartComponents: { number }, EndComponents: { number }, AlphaValue: number): { number }
	local LerpedComponents = table.create(#StartComponents) :: {number}

	for ComponentIndex = 1, #StartComponents do
		LerpedComponents[ComponentIndex] = StartComponents[ComponentIndex] + (EndComponents[ComponentIndex] - StartComponents[ComponentIndex]) * AlphaValue
	end

	return LerpedComponents
end

local function PackValueFromComponents(ComponentValues: { number }, ValueType: string): any
	local PackedValue = ValuePacker.PackValue(ComponentValues, ValueType)

	if PackedValue == nil then
		error(`Bezier does not support packing values of type {ValueType}`)
	end

	return PackedValue
end

local function UnpackControlPoints(ControlPoints: { any }): ({ { number } }, string)
	if #ControlPoints < 2 then
		error("Bezier requires at least 2 control points")
	end

	local ValueType = typeof(ControlPoints[1])
	local FirstPointComponents = ValuePacker.UnpackValue(ControlPoints[1], ValueType)

	if #FirstPointComponents == 0 then
		error(`Bezier does not support control point type {ValueType}`)
	end

	local ComponentCount = #FirstPointComponents
	local UnpackedControlPoints = table.create(#ControlPoints) :: {{number}}
	UnpackedControlPoints[1] = FirstPointComponents

	for ControlPointIndex = 2, #ControlPoints do
		local CurrentControlPoint = ControlPoints[ControlPointIndex]
		local CurrentControlPointType = typeof(CurrentControlPoint)

		if CurrentControlPointType ~= ValueType then
			error(`All control points must share one type; expected {ValueType}, got {CurrentControlPointType} at index {ControlPointIndex}`)
		end

		local CurrentControlPointComponents = ValuePacker.UnpackValue(CurrentControlPoint, ValueType)

		if #CurrentControlPointComponents == 0 then
			error(`Bezier does not support control point type {ValueType}`)
		end

		if #CurrentControlPointComponents ~= ComponentCount then
			error(`Control point component count mismatch at index {ControlPointIndex}`)
		end

		UnpackedControlPoints[ControlPointIndex] = CurrentControlPointComponents
	end

	return UnpackedControlPoints, ValueType
end

local function EvaluateUnpackedControlPoints(UnpackedControlPoints: { { number } }, AlphaValue: number): { number }
	local WorkingControlPoints = table.clone(UnpackedControlPoints)

	for CurrentRowSize = #WorkingControlPoints, 2, -1 do
		for PointIndex = 1, CurrentRowSize - 1 do
			WorkingControlPoints[PointIndex] = LerpComponentValues(WorkingControlPoints[PointIndex], WorkingControlPoints[PointIndex + 1], AlphaValue)
		end
	end

	return WorkingControlPoints[1]
end

local function NormalizeVectorComponentsIfNeeded(ComponentValues: { number }, ValueType: string): { number }
	if ValueType == "Vector2" then
		local Magnitude = math.sqrt(ComponentValues[1] * ComponentValues[1] + ComponentValues[2] * ComponentValues[2])

		if Magnitude == 0 then
			return ComponentValues
		end

		return {
			ComponentValues[1] / Magnitude,
			ComponentValues[2] / Magnitude,
		}
	elseif ValueType == "Vector3" then
		local Magnitude = math.sqrt(
			ComponentValues[1] * ComponentValues[1]
				+ ComponentValues[2] * ComponentValues[2]
				+ ComponentValues[3] * ComponentValues[3]
		)

		if Magnitude == 0 then
			return ComponentValues
		end

		return {
			ComponentValues[1] / Magnitude,
			ComponentValues[2] / Magnitude,
			ComponentValues[3] / Magnitude,
		}
	end

	return ComponentValues
end

--[=[
	@param StartPoint any -- Starting point
	@param EndPoint any -- End point
	@param AlphaValue number -- Interpolation alpha from 0 to 1
	@return any

	Linearly interpolates between two points.
]=]

function Bezier.Lerp(StartPoint: any, EndPoint: any, AlphaValue: number): any
	local StartPointType = typeof(StartPoint)
	if typeof(EndPoint) ~= StartPointType then
		error(`StartPoint and EndPoint must share one type, got {StartPointType} and {typeof(EndPoint)}`)
	end

	local StartComponents = ValuePacker.UnpackValue(StartPoint, StartPointType)
	local EndComponents = ValuePacker.UnpackValue(EndPoint, StartPointType)

	if #StartComponents == 0 then
		error(`Bezier does not support type {StartPointType}`)
	end

	if #StartComponents ~= #EndComponents then
		error(`Component count mismatch while lerping type {StartPointType}`)
	end

	local LerpedComponents = LerpComponentValues(StartComponents, EndComponents, math.clamp(AlphaValue, 0, 1))

	return PackValueFromComponents(LerpedComponents, StartPointType)
end

--[=[
	@param ControlPoints {any} -- Curve control points, minimum of 2
	@param AlphaValue number -- Position on curve from 0 to 1
	@return any

	Evaluates a Bezier curve at t using De Casteljau's algorithm.
]=]

function Bezier.Evaluate(ControlPoints: { any }, AlphaValue: number): any
	local UnpackedControlPoints, ValueType = UnpackControlPoints(ControlPoints)
	local ClampedAlphaValue = math.clamp(AlphaValue, 0, 1)
	local EvaluatedComponents = EvaluateUnpackedControlPoints(UnpackedControlPoints, ClampedAlphaValue)

	return PackValueFromComponents(EvaluatedComponents, ValueType)
end

--[=[
	@param StartPoint any -- Start point
	@param ControlPoint any -- Handle point
	@param EndPoint any -- End point
	@param AlphaValue number -- Position on curve from 0 to 1
	@return any

	Evaluates a quadratic Bezier curve (3 points) at t.
]=]

function Bezier.Quadratic(StartPoint: any, ControlPoint: any, EndPoint: any, AlphaValue: number): any
	return Bezier.Evaluate({ StartPoint, ControlPoint, EndPoint }, AlphaValue)
end

--[=[
	@param StartPoint any -- Start point
	@param FirstControlPoint any -- First handle point
	@param SecondControlPoint any -- Second handle point
	@param EndPoint any -- End point
	@param AlphaValue number -- Position on curve from 0 to 1
	@return any

	Evaluates a cubic Bezier curve (4 points) at t.
]=]

function Bezier.Cubic(StartPoint: any, FirstControlPoint: any, SecondControlPoint: any, EndPoint: any, AlphaValue: number): any
	return Bezier.Evaluate({ StartPoint, FirstControlPoint, SecondControlPoint, EndPoint }, AlphaValue)
end

--[=[
	@param ControlPoints {any} -- Curve control points, minimum of 2
	@param AlphaValue number -- Position on curve from 0 to 1
	@return any

	Gets a tangent direction vector/value at t.

	For Vector2 and Vector3 points, this returns a unit direction when possible.
	For other supported types, this returns the packed derivative in that same type.
]=]

function Bezier.Tangent(ControlPoints: { any }, AlphaValue: number): any
	local UnpackedControlPoints, ValueType = UnpackControlPoints(ControlPoints)
	local DerivativeControlPoints = {}
	local CurveDegree = #UnpackedControlPoints - 1

	for ControlPointIndex = 1, CurveDegree do
		local NextControlPointComponents = UnpackedControlPoints[ControlPointIndex + 1]
		local CurrentControlPointComponents = UnpackedControlPoints[ControlPointIndex]
		local DerivativeComponents = table.create(#CurrentControlPointComponents) :: {number}

		for ComponentIndex = 1, #CurrentControlPointComponents do
			DerivativeComponents[ComponentIndex] = (NextControlPointComponents[ComponentIndex] - CurrentControlPointComponents[ComponentIndex]) * CurveDegree
		end

		DerivativeControlPoints[ControlPointIndex] = DerivativeComponents
	end

	local ClampedAlphaValue = math.clamp(AlphaValue, 0, 1)
	local TangentComponents = EvaluateUnpackedControlPoints(DerivativeControlPoints, ClampedAlphaValue)
	local NormalizedTangentComponents = NormalizeVectorComponentsIfNeeded(TangentComponents, ValueType)

	return PackValueFromComponents(NormalizedTangentComponents, ValueType)
end

--[=[
	@param ControlPoints {any} -- Curve control points, minimum of 2
	@param AlphaValue number -- Position on curve from 0 to 1
	@return {any}, {any} -- Left and right control point arrays

	Splits a Bezier curve into left and right curves at t.
]=]

function Bezier.Split(ControlPoints: { any }, AlphaValue: number): ({ any }, { any })
	local UnpackedControlPoints, ValueType = UnpackControlPoints(ControlPoints)
	local ClampedAlphaValue = math.clamp(AlphaValue, 0, 1)
	local WorkingControlPoints = table.clone(UnpackedControlPoints)
	local LeftControlPoints = { WorkingControlPoints[1] }
	local RightControlPoints = { WorkingControlPoints[#WorkingControlPoints] }

	for CurrentRowSize = #WorkingControlPoints, 2, -1 do
		for PointIndex = 1, CurrentRowSize - 1 do
			WorkingControlPoints[PointIndex] = LerpComponentValues(WorkingControlPoints[PointIndex], WorkingControlPoints[PointIndex + 1], ClampedAlphaValue)
		end

		table.insert(LeftControlPoints, WorkingControlPoints[1])
		table.insert(RightControlPoints, 1, WorkingControlPoints[CurrentRowSize - 1])
	end

	local LeftPackedControlPoints = table.create(#LeftControlPoints)
	local RightPackedControlPoints = table.create(#RightControlPoints)

	for ControlPointIndex = 1, #LeftControlPoints do
		LeftPackedControlPoints[ControlPointIndex] = PackValueFromComponents(LeftControlPoints[ControlPointIndex], ValueType)
	end

	for ControlPointIndex = 1, #RightControlPoints do
		RightPackedControlPoints[ControlPointIndex] = PackValueFromComponents(RightControlPoints[ControlPointIndex], ValueType)
	end

	return LeftPackedControlPoints, RightPackedControlPoints
end

--[=[
	@param ControlPoints {any} -- Curve control points, minimum of 2
	@param SegmentCount number -- Number of line segments to generate, minimum 1
	@return {any}

	Samples a Bezier curve into evenly spaced t-steps.
]=]

function Bezier.Sample(ControlPoints: { any }, SegmentCount: number): { any }
	if #ControlPoints < 2 then
		error("Bezier requires at least 2 control points")
	end

	if SegmentCount < 1 then
		error("SegmentCount must be at least 1")
	end

	local RoundedSegmentCount = math.floor(SegmentCount)
	local SampledPoints = table.create(RoundedSegmentCount + 1)

	for SegmentIndex = 0, RoundedSegmentCount do
		SampledPoints[SegmentIndex + 1] = Bezier.Evaluate(ControlPoints, SegmentIndex / RoundedSegmentCount)
	end

	return SampledPoints
end

--[=[
	@param ControlPoints {any} -- Curve control points, minimum of 2
	@param SegmentCount number -- Number of segments for approximation, minimum 1
	@return number

	Approximates curve length by sampling line segments.
]=]

function Bezier.ApproximateLength(ControlPoints: { any }, SegmentCount: number): number
	local SampledPoints = Bezier.Sample(ControlPoints, SegmentCount)
	local TotalLength = 0

	for SampleIndex = 2, #SampledPoints do
		local CurrentSample = SampledPoints[SampleIndex]
		local PreviousSample = SampledPoints[SampleIndex - 1]
		local SampleType = typeof(CurrentSample)
		local CurrentSampleComponents = ValuePacker.UnpackValue(CurrentSample, SampleType)
		local PreviousSampleComponents = ValuePacker.UnpackValue(PreviousSample, SampleType)
		local DistanceSquared = 0

		for ComponentIndex = 1, #CurrentSampleComponents do
			local Delta = CurrentSampleComponents[ComponentIndex] - PreviousSampleComponents[ComponentIndex]
			DistanceSquared += Delta * Delta
		end

		TotalLength += math.sqrt(DistanceSquared)
	end

	return TotalLength
end

return Bezier
