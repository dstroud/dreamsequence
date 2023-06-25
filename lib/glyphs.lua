glyphs = 
  {
    --loop glyph    
    {{1,0},{2,0},{3,0},{0,1},{0,2},{4,2},{4,3},{1,4},{2,4},{3,4}},
    --one-shot glyph  
    {{2,0},{3,1},{0,2},{1,2},{4,2},{3,3},{2,4}},
    -- pause
    {{0,0},{1,0},{3,0},{4,0}, {0,1},{1,1},{3,1},{4,1}, {0,2},{1,2},{3,2},{4,2}, {0,3},{1,3},{3,3},{4,3},  {0,4},{1,4},{3,4},{4,4}},
    -- play
    {{0,0},{1,0}, {0,1},{1,1},{2,1}, {0,2},{1,2},{2,2},{3,2}, {0,3},{1,3},{2,3}, {0,4},{1,4}},
    -- reset/stopped
    {{0,0},{1,0},{2,0},{3,0},{4,0}, {0,1},{1,1},{2,1},{3,1},{4,1}, {0,2},{1,2},{2,2},{3,2},{4,2}, {0,3},{1,3},{2,3},{3,3},{4,3},  {0,4},{1,4},{2,4},{3,4},{4,4}}
  }

glyphs_str = {'playing', 'paused', 'stopped', 'loop', 'one-shot'}

glyphs_str.playing = {
                          {0,0},{1,0}, 
                          {0,1},{1,1},{2,1}, 
                          {0,2},{1,2},{2,2},{3,2}, 
                          {0,3},{1,3},{2,3}, 
                          {0,4},{1,4}
                        }

glyphs_str.paused = {
                          {0,0},{1,0},{3,0},{4,0}, 
                          {0,1},{1,1},{3,1},{4,1}, 
                          {0,2},{1,2},{3,2},{4,2}, 
                          {0,3},{1,3},{3,3},{4,3},  
                          {0,4},{1,4},{3,4},{4,4}
                        }
                        
glyphs_str.stopped = {
                          {0,0},{1,0},{2,0},{3,0},{4,0}, 
                          {0,1},{1,1},{2,1},{3,1},{4,1}, 
                          {0,2},{1,2},{2,2},{3,2},{4,2}, 
                          {0,3},{1,3},{2,3},{3,3},{4,3},  
                          {0,4},{1,4},{2,4},{3,4},{4,4}
                        }
  
  
glyphs_str.loop = {{1,0},{2,0},{3,0},{0,1},{0,2},{4,2},{4,3},{1,4},{2,4},{3,4}}

glyphs_str.one_shot = {{2,0},{3,1},{0,2},{1,2},{4,2},{3,3},{2,4}}
