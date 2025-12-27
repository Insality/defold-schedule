---@class schedule.state
local M = {}

---Internal state
---@type schedule.state
local state = {}


---Reset state to default
function M.reset()
	state = {}
end


---Get the entire state (for serialization)
---@return schedule.state
function M.get_state()
	return state
end


---Set the entire state (for deserialization)
---@param new_state schedule.state
function M.set_state(new_state)
	state = new_state
end


return M

