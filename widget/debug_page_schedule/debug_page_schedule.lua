local schedule = require("schedule.schedule")

local M = {}


---Format time in seconds to readable string
---@param seconds number
---@return string
function M.format_time(seconds)
	if seconds < 0 then
		return "∞"
	end
	if seconds < 60 then
		return string.format("%.1fs", seconds)
	elseif seconds < 3600 then
		return string.format("%.1fm", seconds / 60)
	elseif seconds < 86400 then
		return string.format("%.1fh", seconds / 3600)
	else
		return string.format("%.1fd", seconds / 86400)
	end
end


---Count events by status
---@param events table<string, schedule.event.state>
---@return table<string, number>
function M.count_events_by_status(events)
	local counts = {
		pending = 0,
		active = 0,
		completed = 0,
		cancelled = 0,
		paused = 0,
		aborted = 0,
		failed = 0
	}

	for _, event_state in pairs(events) do
		local status = event_state.status or "pending"
		if counts[status] then
			counts[status] = counts[status] + 1
		else
			counts[status] = 1
		end
	end

	return counts
end


---Get total event count
---@param events table<string, schedule.event.state>
---@return number
function M.count_total_events(events)
	local count = 0
	for _ in pairs(events) do
		count = count + 1
	end
	return count
end


---@param druid druid.instance
---@param properties_panel widget.properties_panel
function M.render_properties_panel(druid, properties_panel)
	properties_panel:next_scene()
	properties_panel:set_header("Schedule Panel")

	local state = schedule.get_state()
	local events = state.events or {}
	local total_count = M.count_total_events(events)
	local status_counts = M.count_events_by_status(events)

	-- Total event count
	properties_panel:add_text(function(text)
		text:set_text_property("Total Events")
		text:set_text_value(tostring(total_count))
	end)

	-- Status breakdown
	if total_count > 0 then
		properties_panel:add_text(function(text)
			local status_text = string.format("Pending: %d | Active: %d | Completed: %d | Cancelled: %d | Paused: %d",
				status_counts.pending or 0,
				status_counts.active or 0,
				status_counts.completed or 0,
				status_counts.cancelled or 0,
				status_counts.paused or 0)
			text:set_text_property("Status Breakdown")
			text:set_text_value(status_text)
		end)
	end

	-- Group events by status for display
	local events_by_status = {
		pending = {},
		active = {},
		completed = {},
		cancelled = {},
		paused = {},
		aborted = {},
		failed = {}
	}

	for event_id, event_state in pairs(events) do
		local status = event_state.status or "pending"
		if events_by_status[status] then
			table.insert(events_by_status[status], { id = event_id, state = event_state })
		end
	end

	-- Display events grouped by status
	local status_order = { "active", "pending", "paused", "completed", "cancelled", "aborted", "failed" }
	for _, status in ipairs(status_order) do
		local status_events = events_by_status[status]
		if #status_events > 0 then
			-- Status header
			properties_panel:add_text(function(text)
				text:set_text_property("")
				text:set_text_value("── " .. string.upper(status) .. " (" .. #status_events .. ") ──")
			end)

			-- Sort events by event_id for consistent display
			table.sort(status_events, function(a, b)
				return a.id < b.id
			end)

			-- Event buttons
			for _, event_data in ipairs(status_events) do
				local event_id = event_data.id
				local event_state = event_data.state
				local event = schedule.get(event_id)

				properties_panel:add_button(function(button)
					local category = event_state.category or "none"
					local time_info = ""
					
					if event then
						local time_left = event:get_time_left()
						local time_to_start = event:get_time_to_start()
						
						if event_state.status == "active" then
							if time_left == -1 then
								time_info = " [∞]"
							else
								time_info = " [" .. M.format_time(time_left) .. " left]"
							end
						elseif event_state.status == "pending" then
							if time_to_start > 0 then
								time_info = " [starts in " .. M.format_time(time_to_start) .. "]"
							else
								time_info = " [ready]"
							end
						end
					end

					local button_text = event_id
					if category ~= "none" then
						button_text = button_text .. " (" .. category .. ")"
					end
					button_text = button_text .. time_info

					button:set_text_property(button_text)
					button:set_text_button("Inspect")
					button.button.on_click:subscribe(function()
						M.render_event_details_page(schedule, event_id, properties_panel)
					end)
				end)
			end
		end
	end

	-- Reset state button
	properties_panel:add_button(function(button)
		button:set_text_property("Reset Schedule State")
		button:set_text_button("Reset")
		button:set_color("#DC6F6F")
		button.button.on_click:subscribe(function()
			schedule.reset_state()
			properties_panel:set_dirty()
		end)
	end)

	-- Inspect raw state
	properties_panel:add_button(function(button)
		button:set_text_property("Inspect State")
		button:set_text_button("Inspect")
		button.button.on_click:subscribe(function()
			properties_panel:next_scene()
			properties_panel:set_header("Schedule State")
			properties_panel:render_lua_table(state)
		end)
	end)
end


---Render the details page for a specific event
---@param schedule schedule
---@param event_id string
---@param properties_panel widget.properties_panel
function M.render_event_details_page(schedule, event_id, properties_panel)
	properties_panel:next_scene()
	properties_panel:set_header("Event: " .. event_id)

	local event = schedule.get(event_id)
	if not event then
		properties_panel:add_text(function(text)
			text:set_text_property("Error")
			text:set_text_value("Event not found")
		end)
		return
	end

	local event_state = event.state
	local status = event:get_status()

	-- Event ID
	properties_panel:add_text(function(text)
		text:set_text_property("Event ID")
		text:set_text_value(event_id)
	end)

	-- Status
	properties_panel:add_text(function(text)
		text:set_text_property("Status")
		text:set_text_value(status)
	end)

	-- Category
	properties_panel:add_text(function(text)
		local category = event:get_category() or "none"
		text:set_text_property("Category")
		text:set_text_value(category)
	end)

	-- Time information
	local time_left = event:get_time_left()
	local time_to_start = event:get_time_to_start()

	if time_to_start > 0 then
		properties_panel:add_text(function(text)
			text:set_text_property("Time to Start")
			text:set_text_value(M.format_time(time_to_start))
		end)
	end

	if status == "active" then
		properties_panel:add_text(function(text)
			if time_left == -1 then
				text:set_text_property("Time Left")
				text:set_text_value("∞ (infinity)")
			else
				text:set_text_property("Time Left")
				text:set_text_value(M.format_time(time_left))
			end
		end)
	end

	-- Start time
	if event_state.start_time then
		properties_panel:add_text(function(text)
			text:set_text_property("Start Time")
			text:set_text_value(tostring(event_state.start_time))
		end)
	end

	-- End time
	if event_state.end_time then
		properties_panel:add_text(function(text)
			text:set_text_property("End Time")
			text:set_text_value(tostring(event_state.end_time))
		end)
	elseif event_state.infinity then
		properties_panel:add_text(function(text)
			text:set_text_property("End Time")
			text:set_text_value("∞ (infinity)")
		end)
	end

	-- Duration
	if event_state.duration then
		properties_panel:add_text(function(text)
			text:set_text_property("Duration")
			text:set_text_value(M.format_time(event_state.duration))
		end)
	end

	-- Cycle information
	if event_state.cycle then
		properties_panel:add_text(function(text)
			local cycle_type = event_state.cycle.type or "unknown"
			local cycle_info = "Type: " .. cycle_type
			if event_state.cycle_count then
				cycle_info = cycle_info .. " | Count: " .. event_state.cycle_count
			end
			text:set_text_property("Cycle")
			text:set_text_value(cycle_info)
		end)
	end

	-- Conditions
	if event_state.conditions and #event_state.conditions > 0 then
		properties_panel:add_text(function(text)
			text:set_text_property("Conditions")
			text:set_text_value(tostring(#event_state.conditions) .. " condition(s)")
		end)
	end

	-- Payload
	if event_state.payload then
		properties_panel:add_button(function(button)
			button:set_text_property("Payload")
			button:set_text_button("Inspect")
			button.button.on_click:subscribe(function()
				properties_panel:next_scene()
				properties_panel:set_header("Payload: " .. event_id)
				properties_panel:render_lua_table(event_state.payload)
			end)
		end)
	end

	-- Management buttons
	properties_panel:add_text(function(text)
		text:set_text_property("")
		text:set_text_value("── Management ──")
	end)

	-- Start button
	if status == "pending" or status == "cancelled" or status == "aborted" or status == "failed" or status == "paused" then
		properties_panel:add_button(function(button)
			local button_text = status == "paused" and "Resume" or "Start"
			button:set_text_property("Action")
			button:set_text_button(button_text)
			button.button.on_click:subscribe(function()
				if status == "paused" then
					event:resume()
				else
					event:start()
				end
				properties_panel:set_dirty()
			end)
		end)
	end

	-- Finish button
	if status == "active" or status == "pending" then
		properties_panel:add_button(function(button)
			button:set_text_property("Action")
			button:set_text_button("Finish")
			button.button.on_click:subscribe(function()
				event:finish()
				properties_panel:set_dirty()
			end)
		end)
	end

	-- Pause button
	if status == "active" then
		properties_panel:add_button(function(button)
			button:set_text_property("Action")
			button:set_text_button("Pause")
			button.button.on_click:subscribe(function()
				event:pause()
				properties_panel:set_dirty()
			end)
		end)
	end

	-- Cancel button
	if status ~= "completed" then
		properties_panel:add_button(function(button)
			button:set_text_property("Action")
			button:set_text_button("Cancel")
			button:set_color("#DC6F6F")
			button.button.on_click:subscribe(function()
				event:cancel()
				properties_panel:set_dirty()
			end)
		end)
	end

	-- Inspect raw state
	properties_panel:add_button(function(button)
		button:set_text_property("Raw State")
		button:set_text_button("Inspect")
		button.button.on_click:subscribe(function()
			properties_panel:next_scene()
			properties_panel:set_header("Raw State: " .. event_id)
			properties_panel:render_lua_table(event_state)
		end)
	end)
end


return M
