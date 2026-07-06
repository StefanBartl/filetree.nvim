async function main() {
  const { greet } = await import("../util/shared");
  console.log(greet());
}

main();
