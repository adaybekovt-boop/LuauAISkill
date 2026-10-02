--!strict
local Drive = {}
function Drive.valid(throttle: any, steer: any): boolean
	return type(throttle) == "number" and throttle == throttle and math.abs(throttle) <= 1
		and type(steer) == "number" and steer == steer and math.abs(steer) <= 1
end
function Drive.wheels(throttle: number, steer: number, occupied: boolean, age: number): (number, number)
	if not occupied or age > 0.35 or not Drive.valid(throttle, steer) then return 0, 0 end
	return math.clamp(throttle + steer * 0.7, -1, 1) * 16,
		math.clamp(throttle - steer * 0.7, -1, 1) * 16
end
return Drive
