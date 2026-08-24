bool isValidNativeViewGeometry({
  required double x,
  required double y,
  required double width,
  required double height,
}) {
  return x.isFinite &&
      y.isFinite &&
      width.isFinite &&
      height.isFinite &&
      width >= 0 &&
      height >= 0;
}
