extends Control
## The AOT field for the crew's independent Sun check.

var sun_offset := Vector2.ZERO
var detent_set := false
var cursor_degrees := 0.0

func _draw() -> void:
	var center := size * Vector2(0.39, 0.54)
	var radius := minf(size.y * 0.29, size.x * 0.24)
	var line := Color(0.47, 0.59, 0.55)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.011, 0.016, 0.91))
	draw_circle(center, radius + 9.0, Color(0.07, 0.095, 0.10), true, -1.0, true)
	draw_circle(center, radius, Color(0.003, 0.006, 0.010), true, -1.0, true)
	draw_arc(center, radius, 0, TAU, 128, line, 1.0, true)
	var cursor := Vector2.UP.rotated(deg_to_rad(cursor_degrees))
	draw_line(center - cursor * radius, center + cursor * radius, line, 1.0, true)
	draw_line(center - cursor.orthogonal() * 13.0, center + cursor.orthogonal() * 13.0, line, 1.0, true)
	for step in range(1, 6):
		var tick := center + cursor * radius * step / 6.0
		draw_line(tick - cursor.orthogonal() * 5.0, tick + cursor.orthogonal() * 5.0, line, 1.0, true)
	var offset := Vector2(0, -0.83) + sun_offset * 0.105
	if detent_set and offset.length() < 0.97:
		var sun := center + radius * offset
		draw_circle(sun, 11.5, Color(0.96, 0.63, 0.23, 0.12), true, -1.0, true)
		draw_circle(sun, 7.0, Color(1.0, 0.75, 0.42, 0.22), true, -1.0, true)
		draw_circle(sun, 3.4, Color(1.0, 0.95, 0.77), true, -1.0, true)
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 36.0),
		"AOT  ·  %s  ·  CURSOR %03.0f°" % ["DETENT 2 / F" if detent_set else "CHECK DETENT", cursor_degrees],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.72, 0.81, 0.82))
