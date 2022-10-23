-- Lookup table for events
events_lookup = {
  
  {	id= 'clock_tempo', 	event_type= 'param', 	name= 'Tempo', 	value_type= 'inc, set', 				category= 'Global', 	},
  {	id= 'transpose', 	  event_type= 'param', 	name= 'Key', 	value_type= 'inc, set', 	formatter= 'transpose_string', 			category= 'Global', 	},
  {	id= 'generator', 	  event_type= 'function', 	name= 'Generate patterns', 	value_type= 'trigger', 				category= 'Global', 	},
  {	id= 'mode', 	      event_type= 'param', 	name= 'Mode', 	value_type= 'set', 	formatter= 'mode_index_to_name', 			category= 'Global', 	},
  {	id= 'chord_octave', 	event_type= 'param', 	name= 'Chord octave', 	value_type= 'inc, set', 				category= 'Chord', 	},
  {	id= 'chord_type', 	event_type= 'param', 	name= 'Chord type', 	value_type= 'set', 	formatter= 'chord_type', 			category= 'Chord', 	},
  {	id= 'transpose_chord_pattern', 	event_type= 'function', 	name= 'Transpose chord', 	value_type= 'set', 				category= 'Chord', 	},
  {	id= 'shuffle_arp', 	event_type= 'function', 	name= 'Shuffle Arp', 	value_type= 'trigger', 				category= 'Arp', 	},
  {	id= 'rotate_arp', 	event_type= 'function', 	name= 'Rotate Arp', 	value_type= 'set', 				category= 'Arp', 	},
  {	id= 'transpose_arp_pattern', 	event_type= 'function', 	name= 'Transpose arp', 	value_type= 'set', 				category= 'Arp', 	},
  {	id= 'arp_octave', 	event_type= 'param', 	name= 'Arp octave', 	value_type= 'inc, set', 				category= 'Arp', 	},
  {	id= 'arp_chord_type', 	event_type= 'param', 	name= 'Arp chord type', 	value_type= 'set', 	formatter= 'chord_type', 			category= 'Arp', 	},
  {	id= 'arp_mode', 	event_type= 'param', 	name= 'Arp mode', 	value_type= 'set', 				category= 'Arp', 	},
  {	id= 'chord_div_index', 	event_type= 'param', 	name= 'Chord step length', 	value_type= 'set', 	formatter= 'divisions_string', 	action= 'set_div', 	action_var= 'chord', 	category= 'Chord', 	},
  {	id= 'chord_duration_index', 	event_type= 'param', 	name= 'Chord duration', 	value_type= 'inc, set', 	formatter= 'divisions_string', 	action= 'set_duration', 	action_var= 'chord', 	category= 'Chord', 	},
  {	id= 'chord_dest', 	event_type= 'param', 	name= 'Chord destination', 	value_type= 'set', 		action= 'menu_update', 		category= 'Chord', 	},
  {	id= 'arp_div_index', 	event_type= 'param', 	name= 'Arp step length', 	value_type= 'set', 	formatter= 'divisions_string', 	action= 'set_div', 	action_var= 'arp', 	category= 'Arp', 	},
  
  }