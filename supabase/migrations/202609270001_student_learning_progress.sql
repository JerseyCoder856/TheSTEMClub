begin;

alter table public.courses
  add column if not exists pathway text not null default 'Programming';
alter table public.courses
  drop constraint if exists courses_pathway_check;
alter table public.courses
  add constraint courses_pathway_check
  check (pathway in ('Electronics','Programming','3D Design','Environmentals'));

alter table public.lessons
  add column if not exists xp_reward integer not null default 25
  check (xp_reward between 1 and 100);

create table if not exists public.member_certificates (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.memberships(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  certificate_code text not null unique default ('TSC-CERT-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
  awarded_at timestamptz not null default now(),
  unique (member_id,course_id)
);
alter table public.member_certificates enable row level security;
drop policy if exists member_certificates_read_own on public.member_certificates;
create policy member_certificates_read_own on public.member_certificates
  for select to authenticated
  using (member_id in (select id from public.memberships where profile_id=auth.uid()) or public.is_admin());
grant select on public.member_certificates to authenticated;

-- Students can read their progress, but only the RPC may create completion records.
drop policy if exists progress_own_all on public.lesson_progress;
drop policy if exists progress_own_read on public.lesson_progress;
create policy progress_own_read on public.lesson_progress for select to authenticated
  using (member_id in (select id from public.memberships where profile_id=auth.uid()) or public.is_admin());
revoke insert, update, delete on public.lesson_progress from authenticated;
grant select on public.lesson_progress to authenticated;

-- Seed four real learning pathways without overwriting any existing course content.
insert into public.courses (title,slug,summary,pathway,access_level,published,position)
values
  ('Electronics Foundations','stem-path-electronics','Build confidence with circuits, components, sensors, and safe testing.','Electronics','all_members',true,10),
  ('Programming Foundations','stem-path-programming','Learn computational thinking, Python fundamentals, and interactive projects.','Programming','all_members',true,20),
  ('3D Design Foundations','stem-path-3d-design','Move from sketches to measured CAD models and printable prototypes.','3D Design','all_members',true,30),
  ('Environmental STEM','stem-path-environmentals','Use data and engineering to understand ecosystems and design sustainable solutions.','Environmentals','all_members',true,40)
on conflict (slug) do nothing;

insert into public.course_modules (course_id,title,description,position,published)
select c.id,m.title,m.description,m.position,true
from public.courses c
join (values
  ('stem-path-electronics','Circuit Safety and Tools','Recognize components and use a breadboard safely.',1),
  ('stem-path-electronics','Build and Measure','Make a complete low-voltage circuit and test it.',2),
  ('stem-path-electronics','Sensors and Control','Read sensor signals and use them to control an output.',3),
  ('stem-path-programming','Think in Steps','Represent a problem as precise instructions and test cases.',1),
  ('stem-path-programming','Python Building Blocks','Use values, decisions, loops, and functions.',2),
  ('stem-path-programming','Create an Interactive Project','Combine input, logic, and feedback in a small program.',3),
  ('stem-path-3d-design','Sketch and Measure','Plan a useful object and translate dimensions into a model.',1),
  ('stem-path-3d-design','Model with Constraints','Build editable parts with dimensions and simple features.',2),
  ('stem-path-3d-design','Prepare a Prototype','Check fit, print orientation, and iterate from test results.',3),
  ('stem-path-environmentals','Observe a System','Collect repeatable observations about a local environment.',1),
  ('stem-path-environmentals','Analyze Evidence','Organize measurements and distinguish evidence from assumptions.',2),
  ('stem-path-environmentals','Design for Impact','Prototype and evaluate a practical sustainability improvement.',3)
) as m(slug,title,description,position) on c.slug=m.slug
on conflict (course_id,position) do nothing;

insert into public.lessons (module_id,title,content,project_instructions,position,published,xp_reward)
select cm.id,lesson_seed.title,lesson_seed.content,lesson_seed.project_instructions,lesson_seed.lesson_position,true,25
from public.courses c
join public.course_modules cm on cm.course_id=c.id
join (values
  ('stem-path-electronics',1,1,'Identify circuit parts','A circuit needs a source, a complete conducting path, and a load. A battery provides electrical potential; wires and breadboard rows form paths; a resistor limits current; and an LED converts electrical energy to light. Components must be connected with the correct polarity when they are directional.','Draw a labeled circuit with one battery, one resistor, and one LED. Mark the positive and negative sides.'),
  ('stem-path-electronics',1,2,'Use a breadboard safely','Breadboard contact groups are connected internally. On a typical solderless board, each five-hole terminal strip is connected across a row, while long side rails distribute power. The center gap separates the two sides. Check the board layout before connecting power; never short the positive and ground rails.','With power disconnected, use a continuity tester or board diagram to mark which holes share a connection.'),
  ('stem-path-electronics',2,1,'Choose a current-limiting resistor','An LED requires a resistor in series. Estimate resistance with Ohm’s law: R = (Vsupply - VLED) / I. For a 5 V supply, a 2 V LED, and 0.01 A target current, R = 300 ohms. Choose a standard value at or above the estimate and check component ratings.','Calculate a safe resistor for a 3.3 V output, a 2.0 V LED, and 0.008 A target current. Record assumptions.'),
  ('stem-path-electronics',2,2,'Test a complete LED circuit','Build with power disconnected, verify the resistor is in series, inspect for rail shorts, then connect the low-voltage source. If the LED stays dark, disconnect power and check polarity, row connections, and resistor placement before trying again. Change one thing at a time.','Build a low-voltage LED circuit, sketch its actual breadboard rows, and note one test you used to verify it.'),
  ('stem-path-electronics',3,1,'Read a sensor signal','Sensors convert a physical condition into an electrical signal. A photoresistor in a voltage divider produces a voltage that changes with light. A controller can measure that voltage with an analog input. Calibration means recording readings under known conditions rather than guessing a threshold.','Record three sensor readings in bright, medium, and dim conditions. Keep the setup and measurement interval consistent.'),
  ('stem-path-electronics',3,2,'Control an output with a threshold','A threshold rule maps a measured input to an action. Add a dead band or hysteresis so an output does not rapidly switch when a reading sits near the threshold. Test boundary values and document what happens when the sensor is disconnected.','Write a short decision table for a light sensor that switches an LED on when the room is dim.'),
  ('stem-path-programming',1,1,'Decompose a problem','An algorithm is a finite sequence of steps that transforms inputs into outputs. Decompose a large task into smaller operations, state assumptions, and define what a successful result looks like. A useful test includes ordinary values and boundary cases.','Describe the steps for a program that converts minutes into hours and remaining minutes.'),
  ('stem-path-programming',1,2,'Trace and test an algorithm','A trace table records variable values after each instruction. Tracing a small example reveals ordering errors and helps test edge cases such as zero, a negative value, or a value at a limit. Tests should have an expected result before the code runs.','Create a trace table for a loop that adds the integers from 1 through 5. State the expected total.'),
  ('stem-path-programming',2,1,'Use values and decisions','Variables name values that may change. A conditional selects a path based on a Boolean expression. Make conditions explicit and ensure every expected input has a defined outcome, including invalid input.','Write pseudocode that classifies a temperature as cold, comfortable, or warm, including exact boundary values.'),
  ('stem-path-programming',2,2,'Repeat work with loops','A loop repeats a block while a condition remains true or for each item in a collection. A loop needs a clear stopping condition; otherwise it can run forever. Test the first and last iterations and check whether a range includes its endpoint.','Write pseudocode that counts how many readings in a list are above a chosen threshold.'),
  ('stem-path-programming',3,1,'Organize code with functions','A function packages a task behind a name and inputs, and may return a result. Small functions are easier to test when each has one responsibility. Document units, valid ranges, and what happens for invalid values.','Design a function that converts a distance in centimeters to inches. List two tests with expected outputs.'),
  ('stem-path-programming',3,2,'Build and debug a small program','Debugging is a repeatable process: reproduce the issue, inspect inputs and state, form one hypothesis, change one thing, and rerun the same tests. Separate interface code from calculations so the core logic can be tested directly.','Create a small interactive calculator or sensor-data summary. Include at least three test cases and explain one bug you fixed.'),
  ('stem-path-3d-design',1,1,'Turn a need into requirements','A useful design begins with the user and the problem. Translate needs into measurable requirements such as maximum size, load, material, access, and safety. A sketch should show key dimensions and identify which features must fit together.','Choose a small desk organizer problem. Write three measurable requirements and sketch a top and side view.'),
  ('stem-path-3d-design',1,2,'Measure and plan tolerances','Measurements have uncertainty. A fit between two parts needs a tolerance: the permitted difference between nominal dimensions and actual manufactured dimensions. Account for the process and material instead of assuming a model prints exactly to size.','Measure a real object twice. Record units, the two readings, their difference, and a clearance you would add around it.'),
  ('stem-path-3d-design',2,1,'Build a parametric sketch','A constrained sketch uses dimensions and geometric relations so the model stays predictable when edited. Start with a simple profile, constrain its important edges, and use named dimensions for values likely to change.','Plan a rectangular bracket profile. Identify dimensions, symmetry, and the constraints needed to keep the shape stable.'),
  ('stem-path-3d-design',2,2,'Create a solid feature','Extrusion adds depth to a closed profile; a cut removes material. Keep wall thickness and edge distances suitable for the intended use. Inspect the model from multiple views and check that no unintended gaps or overlapping bodies remain.','Model a simple tray with a flat base and four walls. State its dimensions and minimum wall thickness.'),
  ('stem-path-3d-design',3,1,'Prepare a printable prototype','Print orientation affects strength, supports, surface quality, and time. Check the build volume, overhangs, wall thickness, and bed contact. Export the correct body and inspect the sliced preview before printing.','Select an orientation for your tray model and explain the trade-off between strength, supports, and print time.'),
  ('stem-path-3d-design',3,2,'Test, measure, and iterate','A prototype is evidence, not a final answer. Compare the printed result against requirements, measure fit, record defects, and change one parameter at a time. Keep revision notes so an improvement can be repeated.','Create a test table with three requirements, measured results, and a next revision for each failed requirement.'),
  ('stem-path-environmentals',1,1,'Define an observation question','A field observation needs a focused question, a location, a unit, a time interval, and a repeatable method. Record context such as weather because it can affect results. Avoid drawing causal conclusions from one observation.','Write a question about shade, temperature, water use, or biodiversity that can be measured safely in your community.'),
  ('stem-path-environmentals',1,2,'Collect consistent measurements','Use the same instrument, location, and interval for each measurement. Record units and note missing or unusual readings instead of silently discarding them. Repeated observations help separate a pattern from random variation.','Plan five repeated measurements for your question. Include a table header with units and a context-notes column.'),
  ('stem-path-environmentals',2,1,'Summarize data honestly','A graph should match the type of data and show units, sample size, and a readable scale. A mean can be distorted by an extreme value; compare it with the range or median. Association alone does not establish cause.','Choose a graph for your measurements and write one evidence-based observation plus one limitation.'),
  ('stem-path-environmentals',2,2,'Compare solution trade-offs','Engineering solutions have costs and benefits across materials, energy, maintenance, accessibility, and environmental impact. State the criteria before comparing options and distinguish measured evidence from estimates.','Compare two possible solutions to your question using at least three criteria and explain which trade-off matters most.'),
  ('stem-path-environmentals',3,1,'Prototype a practical intervention','A prototype makes a proposed solution testable at small scale. Define a baseline, a success metric, and a safe procedure. Consider who uses or maintains the solution and whether it creates unintended effects elsewhere.','Sketch a small intervention for your chosen issue and define how you would measure whether it helps.'),
  ('stem-path-environmentals',3,2,'Evaluate impact and communicate','A responsible project reports methods, results, uncertainty, and next steps. Compare the final measurement with the baseline using the same method. Credit collaborators and avoid claiming more impact than the evidence supports.','Prepare a short project summary with question, method, result, limitation, and a next test.')
) as lesson_seed(pathway_slug,module_position,lesson_position,title,content,project_instructions)
  on lesson_seed.pathway_slug=c.slug and lesson_seed.module_position=cm.position
on conflict (module_id,position) do nothing;

create or replace function public.complete_student_lesson(target_lesson uuid)
returns table(completed boolean, points_awarded integer, total_xp bigint, certificate_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_key uuid;
  course_key uuid;
  reward integer;
  completion_inserted integer;
  cert_code text;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles p where p.id=auth.uid() and p.account_status='active'
  ) then raise exception 'An active student account is required'; end if;

  select m.id into member_key
  from public.memberships m
  join public.profiles p on p.id=m.profile_id
  where p.id=auth.uid() and p.account_status='active' and m.status='active';
  if member_key is null then raise exception 'An active membership is required'; end if;

  select c.id,l.xp_reward into course_key,reward
  from public.lessons l
  join public.course_modules cm on cm.id=l.module_id and cm.published
  join public.courses c on c.id=cm.course_id and c.published
  where l.id=target_lesson and l.published;
  if course_key is null then raise exception 'Published lesson not found'; end if;

  insert into public.lesson_progress(member_id,lesson_id)
  values(member_key,target_lesson)
  on conflict(member_id,lesson_id) do nothing;
  get diagnostics completion_inserted = row_count;

  if completion_inserted=1 then
    insert into public.point_transactions(member_id,amount,reason,awarded_by,source_key)
    values(member_key,reward,'Lesson completed',auth.uid(),'lesson:'||member_key::text||':'||target_lesson::text)
    on conflict(source_key) do nothing;
  end if;

  if not exists (
    select 1 from public.lessons remaining
    join public.course_modules remaining_module on remaining_module.id=remaining.module_id
    where remaining_module.course_id=course_key and remaining_module.published and remaining.published
      and not exists (select 1 from public.lesson_progress done where done.member_id=member_key and done.lesson_id=remaining.id)
  ) then
    insert into public.member_certificates(member_id,course_id)
    values(member_key,course_key)
    on conflict(member_id,course_id) do nothing;
  end if;

  select certificate_code into cert_code from public.member_certificates
  where member_id=member_key and course_id=course_key;
  return query select completion_inserted=1,case when completion_inserted=1 then reward else 0 end,
    coalesce((select sum(pt.amount)::bigint from public.point_transactions pt where pt.member_id=member_key and pt.amount>0),0),cert_code;
end;
$$;
revoke all on function public.complete_student_lesson(uuid) from public;
grant execute on function public.complete_student_lesson(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;