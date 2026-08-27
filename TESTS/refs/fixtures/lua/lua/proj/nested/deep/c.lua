-- Covers the parenthesis-less string call form `require "mod"`, which the lua
-- provider claims to handle alongside `require("mod")` — a.lua and b.lua use
-- the parenthesised form, so without this file that branch is never exercised.
local shared = require "proj.util.shared"
print(shared.greet())
