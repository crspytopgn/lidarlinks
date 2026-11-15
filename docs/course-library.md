# Courses page

Main menu > **Courses** lists every course the game can play and lets the
player manage them without leaving the game. Code:
`game/scripts/ui/courses_panel.gd` (the page),
`game/scripts/course/course_library.gd` (what each course is, add, delete,
hide) and `game/scripts/realcourse/real_course_update.gd` (Update).
Tests: `game/tests/course_library_tests.gd`.

## What each kind of course allows

| Kind | Where it lives | Delete | Hide | Update |
| --- | --- | --- | --- | --- |
| Built in (Kettle Hollow) | `res://assets/courses/` | no | no | comes with each game update |
| Your design | `user://courses/*.olc` | yes | no | not needed: designs are drawn with the newest look every time they load |
| Real course | `user://courses/*.olc`, `source.kind = "openstreetmap"` | yes | no | yes |
| Links 2003 | the player's game folder or picked discs | never | yes | no |
| Added course | desktop: `user://courses/added/`; browser: IndexedDB (`game/web/game_files.js`) | yes | no | no |

Delete asks a second time on the same button. Deleting a design also removes
its `.photo.jpg` / `.ground.png` beside it, unless another course (a club's
other course) still points at the same file. Nothing outside
`user://courses` is ever deleted: the player's own Links 2003 files are only
hidden. Hidden paths are kept in `user://settings.cfg` under
`[courses] hidden`, and the round setup and online pages leave them out
(`CourseLibrary.shown`). Career, tournaments and resume still find them.

## Adding

- Desktop: one **Add a course...** button takes `.olc`, `.crz`/`.rng`
  (companions `.sha`/`.tip` with the same name come along) or a course's
  `.zip` download (unpacked with `ZIPReader`). Links course files are copied
  to `user://courses/added/`; `.olc` files are saved as designs under a
  free name, with their photo if it sits beside them.
- Browser: **Add a course file (.olc)...** uses the designer's file picker;
  **Add a Links course (.zip, .crz)...** is the existing add-on picker
  (`olFiles.pickCourses`). `olFiles.added` and `olFiles.removeCourse` list
  and remove add-ons.

## Update (real courses)

Every real-course build now saves in its `source`:

- `place`: the search result it was built from (`name`, `lat`, `lon`, `box`,
  `golf`), so the same area is fetched again;
- `map_name`: the course's name in the map (a club with several courses
  builds them all; Update keeps the one with this name);
- `builder`: `RealCourseFetcher.BUILDER_VERSION`;
- `built`: the date.

**Bump `RealCourseFetcher.BUILDER_VERSION` whenever a change to the
real-course builder makes better courses**: older courses then say "built
with an older builder" on the Courses page. Courses built before this page
have no `place`; Update searches round their saved centre instead.

Update runs the normal build, then saves over the same file, keeping the
course's name (even if it was renamed in the designer) and refreshing the
aerial photo and ground pictures. Changes made to the course in the designer
are replaced, which the page says before the second press. If the build
fails or is cancelled, the old file is untouched.
