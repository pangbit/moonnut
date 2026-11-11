///|
test "status uses exact flags and preserves unknown values" {
  assert_eq(status_flags("OL CHRG"), ["OL", "CHRG"])
  assert_eq(status_flags("OB LB"), ["OB", "LB"])
  assert_eq(status_flags("  OL   FUTURE  "), ["OL", "FUTURE"])
  assert_eq(status_flags(""), [])
  assert_false(status_flags("NOL OLB").contains("OL"))
  assert_false(status_flags("ol").contains("OL"))
}
