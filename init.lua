local fix_missing_callbacks = false
local registered_callbacks = {}

local orig_register_node = minetest.register_node
local orig_set_node = minetest.set_node
local orig_remove_node = minetest.remove_node
local orig_swap_node = minetest.swap_node

local table_clone = function(table) 
	if type(table) ~= "table" then return table end -- no need to copy
	local newtable = {}

	for idx, item in pairs(table) do
		if type(item) == "table" then newtable[idx] = table_clone(item)
		else newtable[idx] = item end
	end

	return newtable
end

local function is_valid_pos(pos)
	if not pos or not pos.x or not pos.y or not pos.z then return false end
	if type(pos.x) ~= "number" or type(pos.y) ~= "number" or type(pos.z) ~= "number" then return false end
	return true
end


local function is_valid_node(node)
	if not node then return false end
	if type(node.name) ~= "string" then return false end
	return true
end


local function are_equal(node1, node2)
	return node1.name == node2.name and node1.param1 == node2.param1 and node1.param2 == node2.param2
end


local function fire_changed(pos,new,old)
	-- verify arguments and check if it changed indeed
	if 	not is_valid_pos(pos)	or
		not is_valid_node(old)	or
		not is_valid_node(new)	or
		are_equal(old,new)
	then return end
	
	-- rounding, because falling_node entities call (y-axis) this with floats! Round all axis just to be safe
	pos = {x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5), z = math.floor(pos.z + 0.5)}
	
	-- calling callbacks
	for _,callback in ipairs(registered_callbacks) do
		callback(table_clone(pos),table_clone(new),table_clone(old))
	end	
end

minetest.swap_node = function(pos, node)
	local old = minetest.get_node(pos)
	local new = node
	local res = orig_swap_node(pos,node)
	fire_changed(pos,new,old)
	return res
end

minetest.remove_node = function(pos)
	local old = minetest.get_node(pos)
	local new = {name="air"}
	local res = orig_remove_node(pos)
	fire_changed(pos,new,old)
	return res
end

minetest.set_node = function(pos,node)
	local old = minetest.get_node(pos)
	local new = node
	local res = orig_set_node(pos,node)
	fire_changed(pos,new,old)
	return res
end
minetest.add_node = minetest.set_node

if fix_missing_callbacks then
	minetest.register_node = function(name,def)
		-- pass unknown stuff to original function
		if type(def) ~= "table" then return orig_register_node(name,def) end
		
		-- hook on_place to fix mods not calling callbacks!
		if type(def.on_place) == "function" then
			local o_place = def.on_place
			def.on_place = function(itemstack, placer, pointed_thing)
				return o_place(itemstack, placer, pointed_thing)
			end
		end
		
		return orig_register_node(name,def)
	end
end
	
function minetest.register_on_node_changed(callback)
	if type(callback) ~= "function" then return end
	table.insert(registered_callbacks, callback)
end