--[[
    Copyright (c) 2020-2021 Lukáš Horáček
    https://github.com/lukashoracek/gmod-selfdriving

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <https://www.gnu.org/licenses/>.
--]]

--@name Self-Driving
--@author Lukáš Horáček
--@shared
--@include pid.txt

--// Shared functions
local function getTime()
    return timer.systime()
end

---------------------------------------------
if SERVER then
    local pid = require('pid.txt')

    local inputs = {
        Active = "number";
        Driver = "entity";
        Speed = "number";
        Front = "number";
        Left = "number";
        Right = "number";
    }

    local outputs = {
        Engine = "number";
        Throttle = "number";
        Steer = "number";
        Brake = "number";
        Handbrake = "number";
        Lock = "number";
    }

    --// Settings
    local treatAsTurn = 700
    local vehicleWidth = 62
    local vehicleLength = 280
    local maxSpeed = 1000
    local updateInterval = 0.05
    local throttleAggresivity = 0.75
    local debugOutputEnabled = false

    local maxSteerPerSpeed = 250
    local maxSteerChangePerSpeed = 500

    --// Variables
    local engineActive = false
    local swInControl = true

    local engine = 0
    local throttle = 0
    local steer = 0
    local brake = 0
    local handbrake = 0
    local lock = 0

    local speed = 0

    local front = {
        dist = 0;
    }
    local left = {
        dist = 0;
    }
    local right = {
        dist = 0;
    }

    --// Road
    local straight = false
    local leftTurn = false
    local rightTurn = false

    local leftTurnData = nil
    local rightTurnData = nil

    --// State
    local waitingToTurnLeft = false
    local waitingToTurnRight = false

    local turningLeft = false
    local turningRight = false

    local turnState = nil

    local pullOver = true

    --// Target speed
    local targetSpeed = 0

    --// Offset
    local offset = 0

    --// No turn distances
    local noTurnDist = {
        left = 0;
        right = 0;
    }

    --// Distance counters
    local activeDistanceCounters = {}

    --// PID controllers
    local throttlePID = pid.new(throttleAggresivity, 0, throttleAggresivity * 0.25)
    local steerPID = pid.new(1, 0.001, 0.1)

    --// Last time
    local lastTime = getTime()
    local lastSteer = steer

    --// Functions

    local function createDistanceCounter()
        local counter = {
            createdAt = getTime();
            distance = 0;
        }

        table.insert(activeDistanceCounters, counter)
        return counter
    end

    local function processEngine()
        if engineActive then
            engine = 0
        else
            engine = 1
        end
    end

    local function processThrottle()
        if speed >= targetSpeed then --// Brake
            local b
            if targetSpeed == 0 then
                b = 1
            else
                b = (speed - targetSpeed) / targetSpeed
            end

            throttle = 0
            brake = b
        --[[elseif speed + 25 > targetSpeed then
            throttle = 0
            brake = 0--]]
        elseif speed < targetSpeed then --// Throttle
            local err = 0
            if targetSpeed ~= 0 then
                err = (targetSpeed - speed) / targetSpeed
            end

            local t = throttlePID:process(err)

            throttle = t
            brake = 0
        else
            throttle = 0
            brake = 0
        end
    end

    local function figureOutRoad()
        straight = front.dist > 250 + speed * 0.75
        if turningLeft then
            leftTurn = left.dist > treatAsTurn * 1
        else
            leftTurn = left.dist > treatAsTurn * 2
        end
        if turningRight then
            rightTurn = right.dist > treatAsTurn * 0.5
        else
            rightTurn = right.dist > treatAsTurn
        end

        if leftTurn then
            if not leftTurnData then
                leftTurnData = {
                    leftDist = noTurnDist.right;
                    rightDist = left.dist / 2;
                    maxFrontDistTravel = math.min(front.dist - vehicleLength * 2, left.dist / 2 - vehicleLength * 2);
                }
            end
        else
            leftTurnData = nil
        end
        if rightTurn then
            if not rightTurnData then
                rightTurnData = {
                    leftDist = right.dist / 2;
                    rightDist = noTurnDist.right;
                    maxFrontDistTravel = math.min(front.dist - vehicleLength * 2, right.dist / 3 - vehicleLength * 2);
                }
            end
        else
            rightTurnData = nil
        end
    end

    local function calculateOffset(leftDist, rightDist)
        leftDist = math.min(1500, leftDist)
        rightDist = math.min(1500, rightDist)

        if leftDist < 125 and rightDist < 125 then
            return (leftDist - rightDist) / 1500
        else
            return (leftDist / 2 - rightDist) / 1500
        end
    end

    local function mainProcess()
        --// Cancel turning if already turned
        if turningLeft and not leftTurn and straight then turningLeft = false end
        if turningRight and not rightTurn and straight then turningRight = false end

        --// Turn if waiting to turn and turn is found
        if waitingToTurnLeft and leftTurn then turningLeft = true end
        if waitingToTurnRight and rightTurn then turningRight = true end

        --// Turn state
        if (turningLeft or turningRight) then
            if not turnState then
                turnState = {
                    data = (turningLeft and leftTurnData) or (turningRight and rightTurnData);
                    counter = createDistanceCounter();
                }
            end
        else
            turnState = nil
        end

        --// Speed
        --// Calculate normal target speed based on speed limit and front sensor distance
        --// Also has math for smoother stopping
        local normalTargetSpeed = math.min(maxSpeed, front.dist - 5 - 50 * math.min(1, (100 - speed)^2 / 100^2))

        if turningLeft or turningRight then
            targetSpeed = math.min(maxSpeed * 0.5, normalTargetSpeed)
        else
            if rightTurn then
                targetSpeed = math.min(maxSpeed * 0.75, normalTargetSpeed - 100)
            else
                targetSpeed = math.min(maxSpeed, normalTargetSpeed - maxSpeed * 0.1)
            end

            --// Must not be negative
            targetSpeed = math.max(0, normalTargetSpeed)
        end

        --// Path
        if turningLeft then
            if turnState.counter.distance > turnState.data.maxFrontDistTravel then
                --offset = math.max(left.dist - 250, 750) / 1500
                offset = calculateOffset(left.dist, math.min(front.dist, right.dist)) + 0.5
            else
                offset = -0.1
            end
        elseif turningRight then
            if turnState.counter.distance > turnState.data.maxFrontDistTravel then
                --offset = -math.max(right.dist - 250, 750) / 1500
                offset = calculateOffset(math.max(front.dist, left.dist), right.dist) - 0.5
            else
                offset = 0.1
            end
        else
            if not leftTurn then noTurnDist.left = left.dist end
            if not rightTurn then noTurnDist.right = right.dist end

            local leftDist = left.dist
            local rightDist = right.dist

            if leftTurn then
                leftDist = noTurnDist.left
            end
            if rightTurn then
                rightDist = noTurnDist.right
            end

            --// Pull over
            if pullOver then
                offset = calculateOffset(leftDist, rightDist * 5)

                if math.abs(offset) < 0.05 + (100 - math.min(100, speed)) / 100 then
                    targetSpeed = 0

                    if speed < 50 then
                        offset = 0
                        handbrake = 1
                    end
                else
                    targetSpeed = 250
                end
            else
                offset = calculateOffset(leftDist, rightDist)
            end
        end

        --// If street is too narrow
        local streetWidth = left.dist + right.dist

        if streetWidth < vehicleWidth + speed / 10 then
            print('Street too narrow!')
            targetSpeed = 0
            throttle = 0
            brake = 1
            offset = 0
        end

        --// Lock
        if pullOver and speed < 50 then
            lock = 0
        else
            lock = 1
        end
    end

    local function processSteering()
        steer = -steerPID:process(offset, pullOver or turningLeft or turningRight)

        local requestedSteer = steer

        --// Limit steering per speed
        local maxSteer
        if speed < 0 then
            maxSteer = 1
        else
            maxSteer = maxSteerPerSpeed / speed
        end

        if steer > 0 then
            steer = math.min(maxSteer, steer)
        else
            steer = math.max(-maxSteer, steer)
        end

        --// Limit steering change per speed
        local steerChange = math.abs(lastSteer - steer)
        local maxSteerChange
        if speed < 0 then
            maxSteerChange = 1
        else
            maxSteerChange = maxSteerChangePerSpeed / speed
        end

        maxSteerChange = maxSteerChange * updateInterval

        if steerChange > maxSteerChange then
            if steer > 0 then
                steer = steer - (steerChange - maxSteerChange)
            else
                steer = steer + (steerChange - maxSteerChange)
            end
        end

        --// Store steer
        lastSteer = steer
    end

    local function exportViaWire()
        wire.ports.Engine = engine

        --// Workarounds throttle not working if the same in some situations
        if engineActive then
            wire.ports.Throttle = throttle
        else
            wire.ports.Throttle = 0
        end

        --// At least partially prevent reversing when braking in low speeds
        if speed < 50 then
            if brake > 0 then
                handbrake = 1
                brake = 0
            end
        end

        wire.ports.Steer = steer
        wire.ports.Brake = brake
        wire.ports.Handbrake = handbrake
        wire.ports.Lock = lock
    end

    local function debugOutput()
        print('Straight: ' .. tostring(straight) ..
            '\nLeft: ' .. tostring(leftTurn) ..
            '\nRight: ' .. tostring(rightTurn) ..
            '\nTarget speed: ' .. targetSpeed ..
            '\nTurning left: ' .. tostring(turningLeft) ..
            '\nTurning right: ' .. tostring(turningRight) ..
            '\nThrottle: ' .. tostring(throttle) ..
            '\nBrake: ' .. tostring(brake))

        if turnState then
            print(turnState.counter.distance, turnState.data.maxFrontDistTravel)
        end
    end

    --// Automatic Emergency Braking (AEB)
    local aebTriggered = false
    local lastAEB = getTime()
    local function AEB()
        if aebTriggered and getTime() - lastAEB > 1.5 then
            aebTriggered = false
        end

        if front.dist < 1500 then
            if speed > 350 or (aebTriggered and speed > 10) then
                local brakingTime = 1 * (speed / 1000)
                local brakingDistance = brakingTime * (speed / 2)

                if (brakingDistance + 50) > front.dist or (aebTriggered and (brakingDistance * 1.1 + 50) > front.dist) then
                    aebTriggered = true
                    lastAEB = getTime()

                    brake = 1
                end
            else
                aebTriggered = false
            end
        end
    end

    --// Side Collision Avoidance
    local scaData = {
        lastTime = getTime();
        lastLeft = 0;
        lastRight = 0;
    }
    local function SCA()
        local now = getTime()
        local dt = now - scaData.lastTime

        local leftSpeed = (scaData.lastLeft - left.dist) / dt
        local rightSpeed = (scaData.lastRight - right.dist) / dt

        if left.dist < 40 and right.dist > 100 then
            steer = 1
        elseif right.dist < 40 and left.dist > 100 then
            steer = -1
        end

        scaData.lastTime = now
        scaData.lastLeft = left.dist
        scaData.lastRight = right.dist
    end

    local lastSWInControl = swInControl
    local lastPullOver = pullOver
    local lastAEBTriggered = aebTriggered

    local function process()
        engine = 0
        throttle = 0
        steer = 0
        brake = 0
        handbrake = 0
        lock = 0

        figureOutRoad()

        if swInControl then
            processEngine()
            mainProcess()
            processThrottle()
            processSteering()
        end

        AEB()
        SCA()

        if debugOutputEnabled then
            debugOutput()
        end

        exportViaWire()

        local now = getTime()
        local sinceLast = now - lastTime

        local travelled = speed * sinceLast
        for i=1,#activeDistanceCounters do
            local counter = activeDistanceCounters[i]

            counter.distance = counter.distance + travelled
        end

        lastSWInControl = swInControl
        lastPullOver = pullOver
        lastAEBTriggered = aebTriggered

        lastTime = now
    end

    --// Setup wire
    hook.add('input', 'selfdriving_wire', function(name, value)
        if name == 'Active' then
            engineActive = value == 1
        elseif name == 'Speed' then
            speed = value
        elseif name == 'Front' then
            front.dist = value
        elseif name == 'Left' then
            left.dist = value
        elseif name == 'Right' then
            right.dist = value
        elseif name == 'Driver' then
            swInControl = tostring(value) == '[NULL Entity]'
        end
    end)

    wire.adjustPorts(inputs, outputs)

    --// Setup timer
    timer.create('selfdriving_timer', updateInterval, 0, process)

    --// Keybinds server
    net.receive('selfdriving_keybind', function(len, plr)
        local turn = net.readUInt(3)

        if turn == 1 then
            waitingToTurnLeft = true
            waitingToTurnRight = false

            print('Waiting to turn left')
        elseif turn == 2 then
            waitingToTurnLeft = false
            waitingToTurnRight = true

            print('Waiting to turn right')
        elseif turn == 3 then
            pullOver = not pullOver
            print('Pull over: ' .. tostring(pullOver))
        else
            waitingToTurnLeft = false
            waitingToTurnRight = false

            print('Straight')
        end
    end)
elseif CLIENT then
    --// Keybinds client
    local straightKey = 19 -- I
    local turnLeftKey = 25 -- O
    local turnRightKey = 26 -- P
    local pullOverToggleKey = 22 -- L

    local lastPullOverToggleTime = 0

    local currentTurn = nil
    timer.create('selfdriving_keybinds', 0.05, 0, function()
        if input.isKeyDown(straightKey) and currentTurn ~= 0 then
            currentTurn = 0
            net.start('selfdriving_keybind')
            net.writeUInt(0, 3)
            net.send()
        elseif input.isKeyDown(turnLeftKey) and currentTurn ~= 1 then
            currentTurn = 1
            net.start('selfdriving_keybind')
            net.writeUInt(1, 3)
            net.send()
        elseif input.isKeyDown(turnRightKey) and currentTurn ~= 2 then
            currentTurn = 2
            net.start('selfdriving_keybind')
            net.writeUInt(2, 3)
            net.send()
        elseif input.isKeyDown(pullOverToggleKey) then
            if getTime() - lastPullOverToggleTime < 1.5 then return end
            lastPullOverToggleTime = getTime()

            net.start('selfdriving_keybind')
            net.writeUInt(3, 3)
            net.send()
        end
    end)
end
