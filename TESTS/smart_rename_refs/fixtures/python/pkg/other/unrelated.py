# Negative control: similar-looking module name, must NOT be touched by a
# rename of pkg.util.shared.
from pkg.util.shared_other import greet

print(greet())
