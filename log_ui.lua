require("mod-gui")

--[[ 

Usage
Init logging system by init_logging()
Regularly call update_log_ui for relevant players
You can configure log types via configure_log_type.
Add a log message by log_to_ui.

Each log message has an associated log type, which allows filtering based on log type. 
Each log type can have an associated formatter function which allows postprocessing the message, for example to add the current tick or the log category. A log type can also make changes to the style of its messages
--]]

MAX_LOG_TYPE_SIZE = 50
NUM_LOG_LINES = 50

default_style = {
      font = "default",
      font_color = {r=1, g=1, b=1},
}

-- log_to_ui
-- text: message content
-- type_name: log type
-- data (optional): additional argument that is passed to the formatter function of a log type, if it is set.
function log_to_ui(text, type_name, data)
	if not global.log_data then init_logging() end
	-- Defaults
	if not type_name then type_name = "debug" end
	if not text then text = "" end

	-- Add message to log
	if not global.log_data.log_type_settings[type_name] then configure_log_type(type_name) end
	local type_settings = global.log_data.log_type_settings[type_name]

	local message = {text=text, data=data, type_name = type_name, tick=game.tick}
	message.display_text = type_settings.message_formatter(message)
	table.insert(global.log_data.log_messages, 1, message)

	-- Save number of messages per log type.
	type_settings.log_size = type_settings.log_size + 1 

	-- Delete something if we have too many messages of the type.
	if type_settings.log_size > (type_settings.max_log_size or MAX_LOG_TYPE_SIZE) then 
		local tick = game.tick

		for index = #global.log_data.log_messages, 1, -1 do
			local message = global.log_data.log_messages[index]
			if message.type_name == type_name then 
				table.remove(global.log_data.log_messages, index)
				type_settings.log_size = type_settings.log_size - 1 
				break
			end
		end
	end

	global.log_data.need_update = true
end

-- configure_log_type
-- type_name: 
-- style (optional): style arguments that are set for the display style of the log messages. For example {font_color = {r=1, g=0.2, b=0.2}, font = "default-bold"}. Right now only font_color and font is suggested.
-- max_size (optional): maximum number of log messages for this type that will be saved. We delete the oldest message first. Default is 50.
-- message_formatter (optional): formatter function that determines the actually shown text for each logged message. message_formatter{text=…, type_name=…, tick=…, data=…}. Default format is '[<type_name> | <game_tick>] <text>'.
-- data (optional): type-global argument for formatter function
function configure_log_type(type_name, style, max_size, message_formatter, data)
	if not global.log_data then init_logging() end

	if not global.log_data.log_type_settings[type_name] then global.log_data.log_type_settings[type_name] = {log_size = 0} end

	local t = global.log_data.log_type_settings[type_name]
	t.message_formatter = message_formatter or t.message_formatter or function(message) return "[" .. message.type_name .. " | " .. message.game_tick .. "] " .. message.text end
	t.max_log_size = max_size or t.max_log_size or 50
	t.data = data or t.data
	t.style = style or t.style
end


-- update_log_ui
-- player: player
-- Make sure to call this every tick. Since this is relatively expensive, it schedules itself automatically depending on game speed.
function update_log_ui(player)

	local flow = mod_gui.get_frame_flow(player)
	local frame = flow.log_frame

	if not global.log_data then return end

	if not frame then 
		create_log_ui(player) 
		frame = flow.log_frame
	end

	-- Visibility
	local show = frame.top_flow.show_checkbox.state
	if global.log_data.ui_hidden[player.index] ~= not show then
		frame.scroll_pane.style.visible = show
		frame.type_flow.style.visible = show
		global.log_data.ui_hidden[player.index] = not show
	end

	-- Scheduling
	if game.tick % math.floor(game.speed * 20 + 1) ~= 0 then return end
	if not global.log_data.need_update then return end
	global.log_data.need_update = false


	-- Update
	if show and not global.log_data.ui_paused[player.index] then
		local type_flow = frame.type_flow

		-- Determine which log-types the user wants to see.
		local visible_types = {}
		for log_type, settings in pairs(global.log_data.log_type_settings) do
			local checkbox = type_flow[log_type .. "_checkbox"]
			if checkbox then
				if checkbox.state == true then
					visible_types[log_type] = true
				end
			else
				checkbox = type_flow.add{type="checkbox", name=log_type .. "_checkbox", state=true}
				type_flow.add{type="label", style="label_style", name=log_type .. "_text", caption=log_type}
			end
		end

		-- Determine the set of logs we want to display

		local displayable = {}
		for index, message in pairs(global.log_data.log_messages) do
			if visible_types[message.type_name] then
				displayable[#displayable + 1] = message
				--table.insert(displayable, message)
				if #displayable > NUM_LOG_LINES then break end
			end
		end

		-- Display
		local index = 1
		for _, message in ipairs(displayable) do
			if frame.scroll_pane.table["text_" .. index] then
				local label = frame.scroll_pane.table["text_" .. index]
				label.caption = message.display_text
				for k, v in pairs(default_style) do 
					local st = global.log_data.log_type_settings[message.type_name].style
					label.style[k] = (st and st[k]) or default_style[k]
				end
			else 
				break
			end
			index = index + 1
		end
	end
end


-- init_logging
-- Is called automatically when log_to_gui is called. Calling it manually will reset logged information.
function init_logging()
	-- UI
	global.log_data = {}
	global.log_data.ui_paused = {}
	global.log_data.ui_hidden = {}

	-- content
	global.log_data.log_messages = {}
	global.log_data.log_type_settings = {}
end



-- create_log_ui
-- Is called automatically when update_log_ui(player) is called.
function create_log_ui(player)
	local flow = mod_gui.get_frame_flow(player)
	local frame = flow.log_frame
	if frame and frame.valid then frame.destroy() end
	frame = flow.add{type="frame", name="log_frame", style="frame_style", direction="vertical"}

	local top_flow = frame.add{type="flow", name="top_flow", style="flow_style", direction="horizontal"}
	local title = top_flow.add{type="label", style="label_style", name = "title", caption="Log"}
	title.style.font = "default-frame"
	top_flow.add{type="label", style="label_style", name = "title_show", caption="                    [Show]"}
	top_flow.add{type="checkbox", name="show_checkbox", state=true}

	local scroll_pane = frame.add{type="scroll-pane", name="scroll_pane", style="scroll_pane_style", direction="vertical", caption="foo"}
	local table = scroll_pane.add{type="table", name="table", style="table_style", colspan=1}
	table.style.vertical_spacing = 0
	scroll_pane.style.maximal_height = 500
	scroll_pane.style.maximal_width = 500
	scroll_pane.style.minimal_height = 100
	scroll_pane.style.minimal_width = 50

	for index=1, NUM_LOG_LINES do
		local label = table.add{type="label", style="label_style", name = "text_" .. index, caption="", single_line=true, want_ellipsis=true}
		label.style.top_padding = 0
		label.style.bottom_padding = 0
		--label.style.font_color = {r=1.0, g=0.7, b=0.9}

	end
	local type_flow = frame.add{type="flow", name="type_flow", style="flow_style", direction="horizontal"}
end

function destroy_log_ui(player)
	local fr = mod_gui.get_frame_flow(player).log_frame
	if fr and fr.valid then fr.destroy() end
end
