# Convar reference

What each setting does and why it's in the preset it's in. Every convar was checked against a
full cvar dump of the game for the `cheat` flag; none of these carry it, so they all work in
matchmaking. A few community configs set `r_directlighting`, `r_farz`, `r_drawdecals` or
`cl_disable_ragdolls`. Those are cheat-flagged and silently ignored online, so they're not here.

Legend: **B** = balanced preset, **M** = maxfps preset.

## gameinfo.gi managed block

### Sun shadows (cascaded shadow maps)

| Convar | B | M | Notes |
|---|---|---|---|
| `csm_max_num_cascades_override` | 1 | 0 | Each cascade is a full extra render pass of shadow casters. Default -1 = engine decides, usually 3 or 4. Biggest CPU saving in the pack. |
| `csm_max_shadow_dist_override` | 1024 | 0 | How far sun shadows reach before fading. |
| `lb_csm_override_staticgeo_cascades` / `_value` | true / 0 | true / 0 | Static world geometry only goes into cascade 0. |
| `csm_viewmodel_shadows` | false | false | |
| `lb_csm_draw_translucent`, `lb_csm_draw_alpha_tested` | false | false | Skip translucent and alpha-tested casters (foliage, fences). |
| `csm_max_visible_dist`, `csm_sst_max_visible_dist` | | 1 | M only. Effectively no sun shadow. |

Note `r_citadel_shadow_quality` is a Video menu setting, so it lives in video.txt (0 in both).

### Local light shadows

| Convar | B | M | Notes |
|---|---|---|---|
| `lb_enable_shadow_casting` | false | false | Stationary and dynamic lights stop rendering shadow maps. Lots of lamps on the map. |
| `lb_dynamic_shadow_resolution` / `_base` | true / 128 | true / 32 | For anything still casting, scale resolution with screen size. |
| `lb_shadow_map_cull_empty_mixed` | true | true | |
| `sc_disable_spotlight_shadows` | 1 | 1 | |
| `lb_allow_time_sliced_shadow_map_rendering` | | false | |
| `r_citadel_shadowdb` | | 0 | |

### Particles

| Convar | B | M | Notes |
|---|---|---|---|
| `cl_particle_fallback_base` / `_multiplier` | 2 / 2 | 3 / 3 | Default 0 = never fall back. These tell the engine to use cheaper effect variants when particle sim time is high. The "under load" part is what matters: in a quiet lane nothing changes. |
| `cl_particle_sim_fallback_threshold_ms` | 3 | 1 | Default 6 ms of particle sim per frame before new systems start degrading. 6 ms is a third of a 144 fps frame budget. |
| `r_limit_particle_job_duration` | true | true | |
| `r_particle_cables_cast_shadows` | false | false | |
| `cl_aggregate_particles` | 1 | 1 | |
| `r_particle_cables_render`, `cl_particle_batch_mode`, `r_RainParticleDensity` | | false / 1 / 0 | M only. |

`r_particle_max_detail_level` is a menu setting (video.txt): 1 in B, 0 in M. Default 3.

### Ragdolls, debris, cloth

| Convar | B | M | Notes |
|---|---|---|---|
| `cl_ragdoll_limit` | 0 | 0 | Also set in autoexec because it's archived. Ragdolls are physics sim with no gameplay value. |
| `g_ragdoll_important_maxcount` | 1 | 1 | |
| `func_break_max_pieces` | 1 | 1 | Breakable props spawn one chunk instead of many. |
| `props_break_max_pieces_perframe` | 1 | 0.1 | |
| `presettle_cloth_iterations` | 0 | 0 | Cloth doesn't pre-simulate on spawn. |
| `enable_boneflex`, `r_morphing_enabled`, `r_smooth_morph_normals` | | false / false / 0 | M only. Facial and morph animation off. |
| `r_hair_*`, `animgraph_footlock_enabled`, `animgraph_slowdownonslopes_enabled` | | off | M only. |

### World detail and culling

| Convar | B | M | Notes |
|---|---|---|---|
| `r_grass_quality` | 0 | 0 | 0 off, 4 ultra. Default 2. |
| `sc_dithered_lod_transition_amt` | 0 | 0 | Hard LOD pops instead of dithered cross-fades (the fade renders both LODs). |
| `r_propsmaxdist` | | 800 | M only. Default 1200. Decorative props cull closer. |
| `r_citadel_npr_outlines_max_dist` | | 600 | M only. Default 1000. Hero outlines stop at 600 units. Think about this one: outlines are information. |
| `sc_clutter_density_*`, `sc_instanced_mesh_size_cull_bias` | | see file | M only. Small scattered meshes gone. |
| `r_drawropes`, `r_ropetranslucent`, `rope_subdiv` | | 0 | M only. |

### Decals and impacts (M only)

`r_decals 256` (default 2048), decals fade in 1 ms, per-surface impact effects off, muzzle flash
brightness near zero, character decal resolution 256.

### Panorama UI

| Convar | B | M | Notes |
|---|---|---|---|
| `panorama_disable_blur` | true | true | The frosted-glass blur behind panels is done on the CPU. |
| `panorama_disable_box_shadow` | true | true | |
| `panorama_allow_transitions` | false | false | No animated panel transitions. |
| `panorama_use_new_occlusion_invalidation` | | 1 | |
| `r_dashboard_render_quality` | 0 | 0 | Also a menu setting. |

### Fog

B: volume fog texture 64x64x32 (default 240 wide). M: 32x32x16, `fog_enable 0`,
`volume_fog_intermediate_textures_hdr 0`. `r_citadel_fog_quality` is a menu setting, 0 in both.

### Misc

`r_citadel_drop_shadow_update_frequency 0`, `cl_phys_sleep_enable 1`, wind simulation off
(`wind_system_temporal_smoothing false`, `r_world_wind_strength 0`). M adds `mat_tonemap_bloom_scale 0`,
`cl_retire_low_priority_lights 1`, `mat_max_lighting_complexity 1`, `thumper_use_plane_reflection false`,
`sc_cache_envmap_lpv_lookup false`.

### Deliberately left out

- `sc_disable_baked_lighting true`: present in the M file but commented. It kills lightmaps. Large
  gain, flat ugly map, harder to read corners. Uncomment if you want it.
- `r_directlighting false`, `r_drawdecals false`, `r_farz`, `cl_disable_ragdolls`: cheat-flagged.
- `engine_no_focus_sleep`: default 20 ms sleep when alt-tabbed is what you want.
- Network convars (`cl_interp_ratio`, `cl_updaterate 128`, `rate 786432`): defaults are already
  the maximum. The autoexec pins `cl_updaterate` and `rate` to their defaults so a stale config
  can't lower them. They don't affect fps.

## video.txt (menu settings)

| Key | B | M | Notes |
|---|---|---|---|
| `cpu_level` | 1 | 0 | Engine's own CPU quality knob (0 low .. 2 high). Cloth, particle budgets, misc. The most important single line for a 5700X. |
| `gpu_level` | 3 | 0 | GPU quality. The 9070 XT doesn't care, so B keeps it high. |
| `mem_level`, `gpu_mem_level` | 2 / 2 | 0 / 0 | 16 GB VRAM. No reason to drop in B. |
| `shaderquality` | 1 | 0 | |
| `mat_vsync` | 0 | 0 | |
| `r_low_latency` | 1 | 1 | AMD Anti-Lag 2 (engine integration). Needs Anti-Lag on in Adrenalin. |
| `fps_max` | 0 | 0 | Uncapped. The autoexec sets the same; change it there. |
| `mat_viewportscale` | 1.0 | 1.0 | Render scale. 100 percent. |
| `r_citadel_antialiasing` | 1 | 0 | Free on this GPU, so B keeps it. |
| `r_citadel_upscaling` | 0 | 0 | No FSR. Not needed at native. |
| `r_effects_bloom`, `r_post_bloom`, `r_depth_of_field`, `r_citadel_motion_blur` | off | off | Visibility more than fps. |
| `r_reduce_flash` | 1 | 1 | |
| `r_citadel_shadow_quality` | 0 | 0 | |
| `r_citadel_distancefield_shadows`, `r_screen_space_shadows` | false | false | |
| `r_citadel_ssao`, `r_citadel_ssao_quality`, `r_citadel_distancefield_ao_quality` | 0 | 0 | AO off. GPU-side but free, and it darkens corners. |
| `r_citadel_distancefield_reflections`, `r_citadel_mboit`, `r_arealights` | off | off | |
| `r_citadel_fog_quality`, `r_displacement_mapping`, `r_dashboard_render_quality` | 0 | 0 | |
| `r_particle_max_detail_level` | 1 | 0 | Default 3. |
| `r_particle_shadows`, `r_particle_cables_cast_shadows`, `r_particle_depth_feathering` | off | off | |
| `r_citadel_half_res_noisy_effects` | true | true | Noisy effects (smoke, etc.) at half resolution. |
| `r_texture_stream_mip_bias` | 0 | 1 | 0 = full-res textures. The 9070 XT has the VRAM. M drops one mip for a little less streaming work. Don't go past 4 without the Sinner's Light fix mod (lighting breaks). |
| `r_light_sensitivity_mode` | false | true | Tones down bright flashes. Preference. |
| `r_citadel_outlines` | 1 | 1 | Keep hero outlines. |

## autoexec.cfg

| Convar | B | M | Notes |
|---|---|---|---|
| `fps_max` | 0 | 0 | See README on capping. |
| `fps_max_ui` | 120 | 60 | Menu and loading screen cap. Stops the GPU spinning at 1000 fps in the hero select. |
| `fps_max_tools` | 60 | 60 | |
| `r_low_latency` | 1 | 1 | |
| `engine_low_latency_sleep_after_client_tick` | false | false | Moves the Anti-Lag sleep after client sim. Reports of pacing issues when on. |
| `cl_input_enable_raw_keyboard` | 1 | 1 | |
| `cl_ragdoll_limit` | 0 | 0 | |
| `r_drawtracers_firstperson` | true | false | |
| `citadel_reduce_camera_shake`, `citadel_camera_wobble_disable` | commented | true | |
| `citadel_trooper_glow_disabled`, `citadel_boss_glow_disabled`, `cl_glow_brightness` | commented | on | Minion and boss glow off. Clearer screen, tiny CPU saving. |
| `cl_updaterate`, `rate` | 128 / 786432 | same | Defaults, pinned. |
| `exec autoexec_user.cfg` | | | Your own commands. |
