-- Negative control: similar-looking module name, must NOT be touched by a
-- rename of proj.util.shared (the pattern match is anchored on the closing
-- quote, so "proj.util.shared_other" is a different module entirely).
local other = require("proj.util.shared_other")
print(other)
