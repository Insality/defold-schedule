local schedule = require("schedule.schedule")
local time_utils = require("schedule.internal.schedule_time")

local M = {}


---Format time in seconds to readable string
---@param seconds number
---@return string
function M.format_time(seconds)
	if seconds < 0 then
		return "∞"
	end
	if seconds < 60 then
		return string.format("%ds", math.floor(seconds))
	elseif seconds < 3600 then
		return string.format("%dm", math.floor(seconds / 60))
	elseif seconds < 86400 then
		return string.format("%dh", math.floor(seconds / 3600))
	else
		return string.format("%dd", math.floor(seconds / 86400))
	end
end


---Format timestamp to human readable date string
---@param timestamp number
---@return string
function M.format_timestamp(timestamp)
	if not timestamp then
		return ""
	end
	local year, month, day, hour, minute, second = time_utils.timestamp_to_date(timestamp)
	return string.format("%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
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

	-- Total event count
	properties_panel:add_text(function(text)
		local state = schedule.get_state()
		local events = state.events or {}
		local total_count = M.count_total_events(events)
		text:set_text_property("Total Events")
		text:set_text_value(tostring(total_count))
	end)

	-- Status filter buttons
	local status_configs = {
		{ name = "pending", label = "Pending" },
		{ name = "active", label = "Active" },
		{ name = "paused", label = "Paused" },
		{ name = "completed", label = "Completed" },
		{ name = "cancelled", label = "Cancelled" }
	}

	for _, status_config in ipairs(status_configs) do
		properties_panel:add_button(function(button)
			local state = schedule.get_state()
			local events = state.events or {}
			local status_counts = M.count_events_by_status(events)
			local count = status_counts[status_config.name] or 0
			
			button:set_text_property(status_config.label)
			button:set_text_button(tostring(count))
			button.button.on_click:subscribe(function()
				M.render_status_page(schedule, status_config.name, status_config.label, properties_panel)
			end)
		end)
	end


	-- Reset state button
	properties_panel:add_button(function(button)
		button:set_text_property("Reset")
		button:set_text_button("Reset")
		button:set_color("#DC6F6F")
		button.button.on_click:subscribe(function()
			schedule.reset_state()
			properties_panel:set_dirty()
		end)
	end)

	-- Inspect raw state
	properties_panel:add_button(function(button)
		local state = schedule.get_state()
		button:set_text_property("State")
		button:set_text_button("Inspect")
		button.button.on_click:subscribe(function()
			properties_panel:next_scene()
			properties_panel:set_header("Schedule State")
			properties_panel:render_lua_table(state)
		end)
	end)
end


---Render events filtered by status
---@param schedule schedule
---@param status string
---@param status_label string
---@param properties_panel widget.properties_panel
function M.render_status_page(schedule, status, status_label, properties_panel)
	properties_panel:next_scene()
	properties_panel:set_header(status_label)

	-- Get event IDs once for stable ordering, but fetch fresh data in closures
	local state = schedule.get_state()
	local events = state.events or {}
	local all_event_ids = {}
	for event_id in pairs(events) do
		table.insert(all_event_ids, event_id)
	end
	table.sort(all_event_ids)

	for _, event_id in ipairs(all_event_ids) do
		properties_panel:add_button(function(button)
			-- Fetch fresh event data on each refresh
			local event = schedule.get(event_id)
			if not event then
				gui.set_enabled(button.root, false)
				return
			end
			
			local event_state = event.state
			local current_status = event_state.status or "pending"
			
			-- Only show this button if it matches current status
			if current_status ~= status then
				gui.set_enabled(button.root, false)
				return
			end
			
			local time_info = ""
			local time_left = event:get_time_left()
			local time_to_start = event:get_time_to_start()
			
			if current_status == "active" then
				if time_left == -1 then
					time_info = " ∞"
				else
					time_info = " " .. M.format_time(time_left)
				end
			elseif current_status == "pending" then
				if time_to_start > 0 then
					time_info = " +" .. M.format_time(time_to_start)
				else
					time_info = " ready"
				end
			end

			local button_text = event_id .. time_info

			button:set_text_property(button_text)
			button:set_text_button(event_id)
			button.button.on_click:subscribe(function()
				M.render_event_details_page(schedule, event_id, properties_panel)
			end)
		end)
	end
end


---Render the details page for a specific event
---@param schedule schedule
---@param event_id string
---@param properties_panel widget.properties_panel
function M.render_event_details_page(schedule, event_id, properties_panel)
	properties_panel:next_scene()
	properties_panel:set_header("Event: " .. event_id)

	-- Event ID
	properties_panel:add_text(function(text)
		text:set_text_property("Event ID")
		text:set_text_value(event_id)
	end)

	-- Status
	properties_panel:add_text(function(text)
		local event = schedule.get(event_id)
		if event then
			local status = event:get_status()
			text:set_text_property("Status")
			text:set_text_value(status)
		else
			text:set_text_property("Status")
			text:set_text_value("Not found")
		end
	end)

	-- Category
	properties_panel:add_text(function(text)
		local event = schedule.get(event_id)
		text:set_text_property("Category")
		if event then
			local category = event:get_category() or "none"
			text:set_text_value(category)
		else
			text:set_text_value("N/A")
		end
	end)

	-- Time to start
	properties_panel:add_text(function(text)
		local event = schedule.get(event_id)
		text:set_text_property("Time to Start")
		if event then
			local time_to_start = event:get_time_to_start()
			if time_to_start > 0 then
				text:set_text_value(M.format_time(time_to_start))
			else
				text:set_text_value("Ready")
			end
		else
			text:set_text_value("N/A")
		end
	end)

	-- Time left
	properties_panel:add_text(function(text)
		local event = schedule.get(event_id)
		text:set_text_property("Time Left")
		if event then
			local status = event:get_status()
			if status == "active" then
				local time_left = event:get_time_left()
				if time_left == -1 then
					text:set_text_value("∞ (infinity)")
				else
					text:set_text_value(M.format_time(time_left))
				end
			else
				text:set_text_value("N/A")
			end
		else
			text:set_text_value("N/A")
		end
	end)

	-- Start time
	properties_panel:add_text(function(text)
		local event = schedule.get(event_id)
		text:set_text_property("Start Time")
		if event then
			local event_state = event.state
			if event_state.start_time then
				text:set_text_value(M.format_timestamp(event_state.start_time))
			else
				text:set_text_value("N/A")
			end
		else
			text:set_text_value("N/A")
		end
	end)

	-- End time
	properties_panel:add_text(function(text)
		local event = schedule.get(event_id)
		text:set_text_property("End Time")
		if event then
			local event_state = event.state
			if event_state.end_time then
				text:set_text_value(M.format_timestamp(event_state.end_time))
			elseif event_state.infinity then
				text:set_text_value("∞ (infinity)")
			else
				text:set_text_value("N/A")
			end
		else
			text:set_text_value("N/A")
		end
	end)

	-- Duration
	properties_panel:add_text(function(text)
		local event = schedule.get(event_id)
		text:set_text_property("Duration")
		if event then
			local event_state = event.state
			if event_state.duration then
				text:set_text_value(M.format_time(event_state.duration))
			else
				text:set_text_value("N/A")
			end
		else
			text:set_text_value("N/A")
		end
	end)

	-- Cycle information
	properties_panel:add_text(function(text)
		local event = schedule.get(event_id)
		text:set_text_property("Cycle")
		if event then
			local event_state = event.state
			if event_state.cycle then
				local cycle_type = event_state.cycle.type or "unknown"
				local cycle_info = "Type: " .. cycle_type
				if event_state.cycle_count then
					cycle_info = cycle_info .. " | Count: " .. event_state.cycle_count
				end
				text:set_text_value(cycle_info)
			else
				text:set_text_value("None")
			end
		else
			text:set_text_value("N/A")
		end
	end)

	-- Conditions
	properties_panel:add_text(function(text)
		local event = schedule.get(event_id)
		text:set_text_property("Conditions")
		if event then
			local event_state = event.state
			if event_state.conditions and #event_state.conditions > 0 then
				text:set_text_value(tostring(#event_state.conditions) .. " condition(s)")
			else
				text:set_text_value("None")
			end
		else
			text:set_text_value("N/A")
		end
	end)

	-- Payload
	properties_panel:add_button(function(button)
		local event = schedule.get(event_id)
		if event then
			local event_state = event.state
			if event_state.payload then
				button:set_text_property("Payload")
				button:set_text_button("Inspect")
				button.button.on_click:subscribe(function()
					properties_panel:next_scene()
					properties_panel:set_header("Payload: " .. event_id)
					properties_panel:render_lua_table(event_state.payload)
				end)
			else
				gui.set_enabled(button.root, false)
			end
		else
			gui.set_enabled(button.root, false)
		end
	end)

	-- Management buttons
	-- Start/Resume button
	properties_panel:add_button(function(button)
		local event = schedule.get(event_id)
		if event then
			local status = event:get_status()
			if status == "pending" or status == "cancelled" or status == "aborted" or status == "failed" or status == "paused" then
				local button_text = status == "paused" and "Resume" or "Start"
				button:set_text_property(button_text)
				button:set_text_button(button_text)
				button.button.on_click:subscribe(function()
					if status == "paused" then
						event:resume()
					else
						event:start()
					end
					properties_panel:set_dirty()
				end)
			else
				gui.set_enabled(button.root, false)
			end
		else
			gui.set_enabled(button.root, false)
		end
	end)

	-- Finish button
	properties_panel:add_button(function(button)
		local event = schedule.get(event_id)
		if event then
			local status = event:get_status()
			if status == "active" or status == "pending" then
				button:set_text_property("Finish")
				button:set_text_button("Finish")
				button.button.on_click:subscribe(function()
					event:finish()
					properties_panel:set_dirty()
				end)
			else
				gui.set_enabled(button.root, false)
			end
		else
			gui.set_enabled(button.root, false)
		end
	end)

	-- Pause button
	properties_panel:add_button(function(button)
		local event = schedule.get(event_id)
		if event then
			local status = event:get_status()
			if status == "active" then
				button:set_text_property("Pause")
				button:set_text_button("Pause")
				button.button.on_click:subscribe(function()
					event:pause()
					properties_panel:set_dirty()
				end)
			else
				gui.set_enabled(button.root, false)
			end
		else
			gui.set_enabled(button.root, false)
		end
	end)

	-- Cancel button
	properties_panel:add_button(function(button)
		local event = schedule.get(event_id)
		if event then
			local status = event:get_status()
			if status ~= "completed" then
				button:set_text_property("Cancel")
				button:set_text_button("Cancel")
				button:set_color("#DC6F6F")
				button.button.on_click:subscribe(function()
					event:cancel()
					properties_panel:set_dirty()
				end)
			else
				gui.set_enabled(button.root, false)
			end
		else
			gui.set_enabled(button.root, false)
		end
	end)

	-- Inspect raw state
	properties_panel:add_button(function(button)
		local event = schedule.get(event_id)
		if event then
			local event_state = event.state
			button:set_text_property("Raw State")
			button:set_text_button("Inspect")
			button.button.on_click:subscribe(function()
				properties_panel:next_scene()
				properties_panel:set_header("Raw State: " .. event_id)
				properties_panel:render_lua_table(event_state)
			end)
		else
			gui.set_enabled(button.root, false)
		end
	end)
end


return M
