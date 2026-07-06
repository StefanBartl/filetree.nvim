// Negative control: similar-looking specifier, must NOT be touched by a
// rename of src/util/shared.ts.
import { greet } from "../util/shared_other";

console.log(greet());
