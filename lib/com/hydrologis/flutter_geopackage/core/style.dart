part of flutter_geopackage;

/**
 * Simple style for shapes.
 *
 * @author Andrea Antonello (www.hydrologis.com)
 */
class BasicStyle {
  static final String ID = "_id";
  static final String NAME = "name";
  static final String SIZE = "size";
  static final String FILLCOLOR = "fillcolor";
  static final String STROKECOLOR = "strokecolor";
  static final String FILLALPHA = "fillalpha";
  static final String STROKEALPHA = "strokealpha";
  static final String SHAPE = "shape";
  static final String WIDTH = "width";
  static final String ENABLED = "enabled";
  static final String ORDER = "layerorder";
  static final String DECIMATION = "decimationfactor";
  static final String DASH = "dashpattern";
  static final String MINZOOM = "minzoom";
  static final String MAXZOOM = "maxzoom";
  static final String LABELFIELD = "labelfield";
  static final String LABELSIZE = "labelsize";
  static final String LABELVISIBLE = "labelvisible";
  static final String UNIQUEVALUES = "uniquevalues";
  static final String THEME = "theme";

  int id = 0;
  String name = "";
  double size = 5;
  String fillcolor = "red";
  String strokecolor = "black";
  double fillalpha = 0.3;
  double strokealpha = 1.0;

  /**
   * WKT shape name.
   */
  String shape = "square";

  /**
   * The stroke width.
   */
  double width = 3;

  /**
   * The text size.
   */
  double labelsize = 15;

  /**
   * Field to use for labeling.
   */
  String labelfield = "";

  /**
   * Defines if the labeling is enabled.
   * <p/>
   * <ul>
   * <li>0 = false</li>
   * <li>1 = true</li>
   * </ul>
   */
  int labelvisible = 0;

  /**
   * Defines if the layer is enabled.
   * <p/>
   * <ul>
   * <li>0 = false</li>
   * <li>1 = true</li>
   * </ul>
   */
  int enabled = 0;

  /**
   * Vertical order of the layer.
   */
  int order = 0;

  /**
   * The pattern to dash lines.
   * <p/>
   * <p>The format is an array of floats, the first number being the shift.
   */
  String dashPattern = "";

  /**
   * Min possible zoom level.
   */
  int minZoom = 0;

  /**
   * Max possible zoom level.
   */
  int maxZoom = 22;

  /**
   * Decimation factor for geometries.
   */
  double decimationFactor = 0.0;

  /**
   * If a unique style is defined, the hashmap contains in key the unique value
   * and in value the style to apply.
   */
  Map<String, BasicStyle>? themeMap;

  // String themeField;

  BasicStyle duplicate() {
    BasicStyle dup = new BasicStyle();
    dup.id = id;
    dup.name = name;
    dup.size = size;
    dup.fillcolor = fillcolor;
    dup.strokecolor = strokecolor;
    dup.fillalpha = fillalpha;
    dup.strokealpha = strokealpha;
    dup.shape = shape;
    dup.width = width;
    dup.labelsize = labelsize;
    dup.labelfield = labelfield;
    dup.labelvisible = labelvisible;
    dup.enabled = enabled;
    dup.order = order;
    dup.dashPattern = dashPattern;
    dup.minZoom = minZoom;
    dup.maxZoom = maxZoom;
    dup.decimationFactor = decimationFactor;
    dup.themeMap = themeMap;
    return dup;
  }

  /**
   * @return a string that can be used in a sql insert statement with
   * all the values placed.
   */
  String insertValuesString() {
    StringBuffer sb = new StringBuffer();
    sb.write("'");
    sb.write(name);
    sb.write("', ");
    sb.write(size);
    sb.write(", '");
    sb.write(fillcolor);
    sb.write("', '");
    sb.write(strokecolor);
    sb.write("', ");
    sb.write(fillalpha);
    sb.write(", ");
    sb.write(strokealpha);
    sb.write(", '");
    sb.write(shape);
    sb.write("', ");
    sb.write(width);
    sb.write(", ");
    sb.write(labelsize);
    sb.write(", '");
    sb.write(labelfield);
    sb.write("', ");
    sb.write(labelvisible);
    sb.write(", ");
    sb.write(enabled);
    sb.write(", ");
    sb.write(order);
    sb.write(", '");
    sb.write(dashPattern);
    sb.write("', ");
    sb.write(minZoom);
    sb.write(", ");
    sb.write(maxZoom);
    sb.write(", ");
    sb.write(decimationFactor);
    return sb.toString();
  }

//  /**
//   * Convert string to dash.
//   *
//   * @param dashPattern the string to convert.
//   * @return the dash array or null, if conversion failed.
//   */
//  static List<double> dashFromString( String dashPattern ) {
//    if (dashPattern.trim().length() > 0) {
//      String[] split = dashPattern.split(",");
//      if (split.length > 1) {
//        float[] dash = new float[split.length];
//        for( int i = 0; i < split.length; i++ ) {
//          try {
//            float tmpDash = Float.parseFloat(split[i].trim());
//            dash[i] = tmpDash;
//          } catch (NumberFormatException e) {
//    // GPLog.error("Style", "Can't convert to dash pattern: " + dashPattern, e);
//    return null;
//    }
//    }
//    return dash;
//    }
//    }
//    return null;
//    }
//
//  /**
//   * Convert a dash array to string.
//   *
//   * @param dash  the dash to convert.
//   * @param shift the shift.
//   * @return the string representation.
//   */
//  static String dashToString( List<double> dash, double shift ) {
//  StringBuilder sb = new StringBuilder();
//  if (shift != null)
//  sb.append(shift);
//  for( int i = 0; i < dash.length; i++ ) {
//  if (shift != null || i > 0) {
//  sb.append(",");
//  }
//  sb.append((int) dash[i]);
//  }
//  return sb.toString();
//  }
//
//  static List<float> getDashOnly( float[] shiftAndDash ) {
//  return Arrays.copyOfRange(shiftAndDash, 1, shiftAndDash.length);
//  }
//
//  static float getDashShift( float[] shiftAndDash ) {
//  return shiftAndDash[0];
//  }

//  String getTheme() {
//    if (themeMap != null && themeMap.length > 0 && themeField != null && themeField
//        .trim()
//        .length > 0) {
//      JSONObject root = new JSONObject();
//      JSONObject unique = new JSONObject();
//      root.put(UNIQUEVALUES, unique);
//      JSONObject sub = new JSONObject();
//      unique.put(themeField, sub);
//      for (Entry < String, BasicStyle > entry : themeMap.entrySet() ) {
//    String key = entry.getKey();
//    BasicStyle value = entry.getValue();
//    sub.put(key, value.toJson());
//    }
//    return root.toString();
//    }
//    return "";
//  }

  String toJson() {
    Map<String, dynamic> map = {};
    map[ID] = id;
    map[NAME] = name;
    map[SIZE] = size;
    map[FILLCOLOR] = fillcolor;
    map[STROKECOLOR] = strokecolor;
    map[FILLALPHA] = fillalpha;
    map[STROKEALPHA] = strokealpha;
    map[SHAPE] = shape;
    map[WIDTH] = width;
    map[LABELSIZE] = labelsize;
    map[LABELFIELD] = labelfield;
    map[LABELVISIBLE] = labelvisible;
    map[ENABLED] = enabled;
    map[ORDER] = order;
    map[DASH] = dashPattern;
    map[MINZOOM] = minZoom;
    map[MAXZOOM] = maxZoom;
    map[DECIMATION] = decimationFactor;

    var json = JSON.jsonEncode(map);
    return json;
  }

  void setFromJson(String json) {
    Map<String, dynamic> map = JSON.jsonDecode(json);
    id = map[ID];
    if (map.containsKey(NAME)) name = map[NAME];
    if (map.containsKey(SIZE)) size = double.parse(map[SIZE].toString());
    if (map.containsKey(FILLCOLOR)) fillcolor = map[FILLCOLOR];
    if (map.containsKey(STROKECOLOR)) strokecolor = map[STROKECOLOR];
    if (map.containsKey(FILLALPHA))
      fillalpha = double.parse(map[FILLALPHA].toString());
    if (map.containsKey(STROKEALPHA))
      strokealpha = double.parse(map[STROKEALPHA].toString());
    if (map.containsKey(SHAPE)) shape = map[SHAPE];
    if (map.containsKey(WIDTH)) width = double.parse(map[WIDTH].toString());
    if (map.containsKey(LABELSIZE))
      labelsize = double.parse(map[LABELSIZE].toString());
    if (map.containsKey(LABELFIELD)) labelfield = map[LABELFIELD];
    if (map.containsKey(LABELVISIBLE)) labelvisible = map[LABELVISIBLE];
    if (map.containsKey(ENABLED)) enabled = map[ENABLED];
    if (map.containsKey(ORDER)) order = map[ORDER];
    if (map.containsKey(DASH)) dashPattern = map[DASH];
    if (map.containsKey(MINZOOM)) minZoom = map[MINZOOM];
    if (map.containsKey(MAXZOOM)) maxZoom = map[MAXZOOM];
    if (map.containsKey(DECIMATION))
      decimationFactor = double.parse(map[DECIMATION].toString());
  }

  String toString() {
    try {
//      String jsonStr = getTheme();
//      if (jsonStr.length == 0) {
      return toJson().toString();
//      }
//      return jsonStr;
    } catch (e) {
      print(e);
    }
    return "";
  }
}
