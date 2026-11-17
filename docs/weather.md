# Weather

Settings > Weather (next round) picks the day a round is played in:

- **Always fine** (the default): a sunny day, as before. The Wind setting sets the wind.
- **Realistic for the course**: a day drawn from the course's climate for
  this month, on the round's seed (a shared round gets the same day).
- **Live where it's real**: the weather at a real course right now, from
  [Open-Meteo](https://open-meteo.com) (free, no key; only the course's
  latitude and longitude are sent). Until the reply comes, and at courses
  that aren't real places, the climate's day is used.

## Where the weather comes from

`Climate` (`game/scripts/weather/climate.gd`) puts a course in one of eight
climate zones from where it is (`FreeAmbience.location_of`: the map
location of built-in and real courses, the known places of the disc and
classic courses), what kind of place it is (seaside, desert) and its biome
(snow and lava courses). Each zone has rounded summer and winter values for
cloud cover, the chance of a wet round and how much of that is drizzle, the
mean wind, the chance of mist and the daytime high, eased between by the
month (summer is January in the southern hemisphere). Seaside courses get
30% more wind and more mist. The values are our own rounding of public
climate summaries; Links 2003 had no weather beyond the wind.

`RoundWeather` (`game/scripts/weather/round_weather.gd`) draws the day:
cloud round the zone's mean, rain or drizzle by the wet-round chance (with
a thick deck and a cooler, windier day), a lognormal spread of wind round
the mean, and mist on still days.

## What it changes

- **Play**: only the wind. The day's mean wind picks the round's Wind level
  (`RoundWeather.WIND_LEVEL_UP_TO`) and replaces the Wind setting, unless the
  round has set conditions (round setup, a friend's code, online).
  Links 2003's ball flight has no rain, temperature or air density, and the
  physics is unchanged.
- **Light** (Photoreal): `Scenery.set_weather` dims the sun and softens its
  shadows under cloud (`overcast_of`: scattered cloud keeps the sun out most
  of the time), raises the sky's fill, greys the photographed sky
  (`photo_sky.gdshader` `overcast` and `deck`) and the haze.
- **Mist** thickens the haze (`fog_scale`, up to about 700 m visibility),
  Classic lighting included.
- **Rain**: `RainFx` draws falling streaks round the camera in one
  CPUParticles3D draw (fewer at lower quality, so it runs on the web) and
  plays a rain hiss made from noise at start-up. Birds call less and the
  mowers stay in.
- **Broken cloud** turns the cloud shadows on even when the setting is off.
- The HUD shows the day after the wind: "8 mph, against · Drizzle, 11°C".
