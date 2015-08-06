local fix_missing_callbacks = false
local crash_on_error = true
local crash_hard = false

local registered_callbacks = {}
local node_changed_path = minetest.get_modpath("node_changed")
local mods
local dep_tree = {}

local table_from_file = function(filename)
	local f=io.open(filename,"r")
	if not f then return nil end
	local t = {}
	while true do
		local line = f:read("*line")
		if line == nil then break end
		table.insert(t,line)
	end
	io.close(f)
	return t
end

local ex = {}
ex["node_changed"] = true

local ex_file = table_from_file(node_changed_path.."/exceptions.txt")
if ex_file then
	for i = 1,#ex_file do
		ex[ex_file[i]] = true
	end
end

-- loads a single mod into the tree
local load_mod = function(mod)
	local path = minetest.get_modpath(mod)
	if not path then return end
	
	local mdep = table_from_file(path.."/depends.txt")
	if not mdep then return end
	
	for i = 1,#mdep do
		local line = mdep[i]
		if string.sub(line,-1) == "?" then
			line = string.sub(line,1,string.len(line)-1)
		end
		if dep_tree[line] then
			table.insert(dep_tree[mod],line)
		end
	end
end

-- load entire mod dependency tree
local load_mod_tree = function()
	mods = minetest.get_modnames()
	for i, name in ipairs(mods) do dep_tree[name] = {} end
	for i, name in ipairs(mods) do load_mod(name) end
end

-- 
local get_tree_roots = function()
	local res = {}
	for k,v in pairs(dep_tree) do
		if #v < 1 and not ex[k] then table.insert(res,k) end
	end
	return res
end

load_mod_tree();
local roots = get_tree_roots()
if roots and #roots > 0 then
	print("")
	print("=========================================================")
	print("ERROR: The following mods may load before 'node_changed':")
	print(table.concat(roots, ", "))
	print("=========================================================")
	print("")
	if crash_on_error then
		if crash_hard then error() end
		print(""..nil)
	end
end












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