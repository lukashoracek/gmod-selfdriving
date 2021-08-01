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

--@name PID controller library
--@author Lukáš Horáček
--@shared

local function getTime()
    return timer.systime()
end

return {
    new = function(P, I, D)
        return {
            lastTime = getTime();
            lastError = 0;

            gains = {
                P = P or 1;
                I = I or 1;
                D = D or 1;
            };

            I = 0;

            lastP = 0;
            lastI = 0;
            lastD = 0;

            process = function(self, err, noISave)
                local now = getTime()
                local de = err - self.lastError
                local dt = now - self.lastTime

                local P = err * self.gains.P
                local i = err * dt * self.gains.I
                local D = de / dt * self.gains.D

                local I = self.I + i

                if not noISave then
                    self.I = I
                end

                self.lastTime = now
                self.lastError = err

                self.lastP = P
                self.lastI = I
                self.lastD = D

                return P + I + D
            end;

            print = function(self)
                print(self.lastP, self.lastI, self.lastD)
            end;
        }
    end;
}