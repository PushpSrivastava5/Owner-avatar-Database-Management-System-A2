%%sql create table department (
    dept_id char(3), 
    dept_name varchar(40) not null unique, 
    primary key (dept_id)
); 

create table student (
    first_name varchar(40) not null, 
    last_name varchar(40), 
    student_id char(11) not null,
    address varchar(100),
    contact_number char(10) not null unique, 
    email_id varchar(50) unique, 
    tot_credits numeric not null, 
    dept_id char(3),
    primary key (student_id), 
    check(tot_credits>=0),
    foreign key (dept_id) references department (dept_id) on update cascade on delete cascade
);

create table courses (
    course_id char(6) not null,
    course_name varchar(20) not null unique,
    course_desc text,
    credits numeric not null, 
    dept_id char(3),
    primary key (course_id), 
    check (credits > 0 and substring(course_id from 1 for 3) = dept_id and substring(course_id from 4 for 3) similar to '[0-9][0-9][0-9]'),
    foreign key (dept_id) references department (dept_id) on update cascade on delete cascade
);

create table professor(
    professor_id varchar(10),
    professor_first_name varchar(40) not null,
    professor_last_name varchar(40) not null,
    office_number varchar(20),
    contact_number char(10) not null,
    start_year integer, 
    resign_year integer, 
    dept_id char(3),
    primary key(professor_id),
    check(start_year <= resign_year),
    foreign key(dept_id) references department(dept_id) on update cascade on delete cascade
);

create table course_offers(
    course_id char(6),
    session varchar(9),
    semester integer not null,
    professor_id varchar(10),
    capacity integer, 
    enrollments integer,
    primary key (course_id, session, semester),
    check (semester = 1 or semester = 2),
    foreign key (course_id) references courses(course_id) on update cascade on delete cascade, 
    foreign key (professor_id) references professor(professor_id) on update cascade on delete cascade
);

create table student_courses (
    student_id char(11),
    course_id char(6),
    session varchar(9),
    semester integer,
    grade numeric not null,
    check(grade>=0 and grade<= 10 and (semester=1 or semester =2)),
    foreign key (student_id) references student(student_id) on update cascade on delete cascade, 
    foreign key (course_id, session, semester) references course_offers(course_id, session, semester) on update cascade on delete cascade
);

create table valid_entry(
    dept_id char(3),
    entry_year integer not null, 
    seq_number integer not null,
    foreign key(dept_id) references department(dept_id) on update cascade on delete cascade
);



create or replace function validateStudentId() returns trigger 
as $$
    begin
        if length(new.student_id) <> 10 then
            raise exception 'invalid';
        end if;
        if not exists (select 1 from valid_entry where entry_year = substring(new.student_id from 1 for 4)::Integer and dept_id = substring(new.student_id from 5 for 3) and LPAD(cast(seq_number as varchar), 3, '0') = substring(new.student_id from 8 for 3)) then
            raise exception 'invalid';
        end if;
        return new;
    end;         
$$ language plpgsql;

create or replace trigger validate_student_id before insert on student
    for each row
    execute procedure validateStudentId();


create or replace function UpdateSeqNumber() returns trigger 
as $$
    begin
        update valid_entry set seq_number = 1 + seq_number
            where entry_year = substring(new.student_id from 1 for 4)::Integer and dept_id = substring(new.student_id from 5 for 3); 
        return new;
    end;         
$$ language plpgsql;

create or replace trigger update_seq_number after insert on student
    for each row
    execute procedure UpdateSeqNumber();

create or replace function validateStudentId3() returns trigger 
as $$
    begin
        if length(new.student_id) <> 10 then
            raise exception 'invalid';
        end if;
        if not exists (select 1 from valid_entry where entry_year = substring(new.student_id from 1 for 4)::Integer and dept_id = substring(new.student_id from 5 for 3) and LPAD(cast(seq_number as varchar), 3, '0') = substring(new.student_id from 8 for 3)) then
            raise exception 'invalid';
        end if;
        if new.email_id <> new.student_id || '@' || new.dept_id || '.iitd.ac.in' then 
            raise exception 'invalid';
        end if;
        return new;
    end;         
$$ language plpgsql;

create or replace trigger validate_student_id3 before insert on student
    for each row
    execute procedure validateStudentId3();



create table student_dept_change (
    old_student_id char(11),
    old_dept_id char(3),
    new_dept_id char(3), 
    new_student_id char(11)
);   



create or replace function deptChange() returns trigger 
as $$
    begin
        if (substring(old.student_id from 1 for 4)::Integer< 2022) then
            raise exception 'Entry year must be >= 2022';
        elsif (select count(*) from student_dept_change where old_student_id = old.student_id) > 0 then
            raise exception 'Department can be changed only once';  
        elsif ((select avg(grade) from student_courses where student_id = old.student_id) <= 8.5 or (select count(*) from student_courses where student_id = old.student_id) = 0) then
            raise exception 'Low Grade'; 
        else 
            new.student_id := substring(old.student_id from 1 for 4) || new.dept_id || LPAD(cast((select seq_number from valid_entry where dept_id = new.dept_id and entry_year = substring(old.student_id from 1 for 4)::Integer) as varchar), 3, '0');
            new.email_id := substring(old.email_id from 1 for 4) || new.dept_id || LPAD(cast((select seq_number from valid_entry where dept_id = new.dept_id and entry_year = substring(old.student_id from 1 for 4)::Integer) as varchar), 3, '0') || '@iitd.ac.in';
            update valid_entry set seq_number = seq_number + 1 where dept_id = new.dept_id and entry_year = substring(old.student_id from 1 for 4)::Integer;
        end if;
        return new;
    end;         
$$ language plpgsql;

create or replace trigger log_student_dept_change before update on student
    for each row
    execute procedure deptChange();

create or replace function deptChange1() returns trigger
as $$
    begin 
        insert into student_dept_change values (old.student_id, old.dept_id, new.dept_id, new.student_id);
    return new;
    end;
$$ language plpgsql;

create or replace trigger log_student_dept_change1 after update on student
    for each row
    execute procedure deptChange1();










create materialized view course_eval as
select courses.course_id, student_courses.session, student_courses.semester, count(*) as number_of_students, avg(student_courses.grade) as average_grade, max(student_courses.grade) as max_grade, min(student_courses.grade) as min_grade
from courses join student_courses on courses.course_id = student_courses.course_id
group by courses.course_id, student_courses.session, student_courses.semester;

create or replace function refresh_materialized_view()
returns trigger as $$
begin
    refresh materialized view course_eval;
    return new;
end;
$$ language plpgsql;

create or replace trigger refresh_cross_product_view_trigger
after insert or update on student_courses
for each row
execute function refresh_materialized_view();




create or replace function checkCredits()
returns trigger as 
$$
    begin
        if (select count(*) from student_courses where student_id = new.student_id and session = new.session and semester = new.semester) >= 5 or ((select tot_credits from student where student_id = new.student_id) + (select credits from courses where course_id = new.course_id) > 60) then
            raise exception 'invalid';
        elsif (select credits from courses where course_id = new.course_id) = 5 and substring(new.student_id from 1 for 4) <> substring(new.session from 1 for 4) then
            raise exception 'invalid';
        elsif (select credits from courses where course_id = new.course_id) + (select credits from student_semester_summary where student_id = new.student_id and session = new.session and semester = new.semester) > 26 then
            raise exception 'invalid';
        elsif(select capacity from course_offers where course_id = new.course_id and session = new.session and semester = new.semester) = (select enrollments from course_offers where course_id = new.course_id and session = new.session and semester = new.semester) then
            raise exception 'course is full';
        else
            ALTER TABLE student disable TRIGGER log_student_dept_change;
            ALTER TABLE student disable TRIGGER log_student_dept_change1;

            update student set tot_credits = tot_credits + (select credits from courses where course_id = new.course_id) where student_id = new.student_id;
            ALTER TABLE student enable TRIGGER log_student_dept_change;
            ALTER TABLE student enable TRIGGER log_student_dept_change1;

            update course_offers set enrollments = enrollments + 1 where course_id = new.course_id and session = new.session and semester = new.semester;  
        end if;
        return new;
    end;
$$ language plpgsql;

create or replace trigger update_tot_credits
before insert on student_courses 
for each row
execute procedure checkCredits();


create materialized view student_semester_summary as 
select student_courses.student_id, student_courses.session, student_courses.semester, sum(student_courses.grade*courses.credits)/sum(courses.credits) as sgpa, sum(courses.credits) as credits
from courses join student_courses 
on courses.course_id = student_courses.course_id 
where student_courses.grade >= 5
group by student_courses.semester, student_courses.student_id, student_courses.session;


create or replace function updateInto()
returns trigger as $$
    begin   
        refresh materialized view student_semester_summary;
    return new;
    end;
$$ language plpgsql;

create or replace trigger updateInView 
after update or insert on student_courses
for each row
execute function updateInto();


create or replace function deleteInto()
returns trigger as $$
    begin   
        refresh materialized view student_semester_summary;
        update student set tot_credits = tot_credits - (select credits from courses where course_id = old.course_id) where student_id = old.student_id; 
    return old;
    end;
$$ language plpgsql;

create or replace trigger deleteInView 
after delete on student_courses
for each row
execute function deleteInto();










create or replace function removeCourseOffers() returns trigger
as $$
    begin 
        delete from student_courses where course_id = old.course_id and session = old.session and semester = old.semester;
        return new;
    end;
$$ language plpgsql;

create or replace trigger remove_course_offers after delete on course_offers
    for each row 
    execute procedure removeCourseOffers();

create or replace function addCourse() returns trigger 
as $$ 
    begin 
        if (new.course_id not in (select course_id from courses)) or (new.professor_id not in (select professor_id from professor)) then
            raise exception 'invalid';
        elsif (select count(*) from course_offers where session = new.session and professor_id = new.professor_id) > 4 or (substring(new.session from 1 for 4)::Integer >= (select resign_year from professor where professor_id = new.professor_id)) then 
        raise exception 'invalid';
        end if;
        return new;
    end;
$$ language plpgsql;

create or replace trigger add_course_offers before insert on course_offers
    for each row 
    execute procedure addCourse(); 











create or replace function update_course_id()
returns trigger as $$
begin
  new.course_id = new.dept_id || substring(old.course_id from 4 for 3) where substring(old.course_id from 1 for 3) = old.dept_id; 
  return new;
end;
$$ language plpgsql;

create or replace trigger before_update_courses
before update on courses
for each row
execute procedure update_course_id();



create or replace function dept_update() returns trigger
as $$
begin
    if (TG_OP = 'DELETE' and (select count(*) from student where dept_id = old.dept_id) > 0) then
        raise exception 'Department has students';
    elsif (TG_OP = 'DELETE') then 
        return old;
    else
            update student_courses set course_id = concat(new.dept_id, substring(course_id from 4 for 3)) where substring(course_id from 1 for 3) = old.dept_id;
        return new;
    end if; 
end;
$$ language plpgsql;

create or replace trigger Update_dept before update or delete on department 
    for each row
    execute procedure dept_update();
