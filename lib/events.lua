-- Lookup table for events
events_lookup = {
  
  {'clock_tempo', 'param', 'Tempo', 'inc, set', '', '', '', ''},
  {'transpose', 'param', 'Key', 'inc, set', 'transpose_string', '', '', ''},
  {'generator', 'function', 'Generate patterns', 'trigger', '', '', '', ''},
  {'mode', 'param', 'Mode', 'set', 'mode_index_to_name', '', '', ''},
  {'chord_octave', 'param', 'Chord octave', 'inc, set', '', '', '', ''},
  {'chord_type', 'param', 'Chord type', 'set', 'chord_type', '', '', ''},
  {'transpose_chord_pattern', 'function', 'Transpose chord', 'set', '', '', '', ''},
  {'shuffle_arp', 'function', 'Shuffle Arp', 'trigger', '', '', '', ''},
  {'rotate_arp', 'function', 'Rotate Arp', 'set', '', '', '', ''},
  {'transpose_arp_pattern', 'function', 'Transpose arp', 'set', '', '', '', ''},
  {'arp_octave', 'param', 'Arp octave', 'inc, set', '', '', '', ''},
  {'arp_chord_type', 'param', 'Arp chord type', 'set', 'chord_type', '', '', ''},
  {'arp_mode', 'param', 'Arp mode', 'set', '', '', '', ''},
  {'chord_div_index', 'param', 'Chord step length', 'set', 'divisions_string', 'set_div', 'chord', ''},
  {'chord_duration_index', 'param', 'Chord duration', 'inc, set', 'divisions_string', 'set_duration', 'chord', ''},
  {'chord_dest', 'param', 'Chord destination', 'set', '', 'menu_update', '', ''},
  {'arp_div_index', 'param', 'Arp step length', 'set', 'divisions_string', 'set_div', 'arp', ''},
  
  }