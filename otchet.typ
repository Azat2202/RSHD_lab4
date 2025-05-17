#set text(
  font: "Times New Roman",
  size: 14pt
)
#set quote(block: true)

#align(center)[Министерство науки и высшего образования Российской Федерации]
#align(center)[Федеральное государственное автономное образовательное учреждение]
#align(center)[Высшего образования]
#align(center)[_Факультет Программной Инженерии и Компьютерной Техники_]

#v(8em)

#align(center)[*Лабораторная работа 4 по РСХД*]
#align(center)[Вариант 98523]

#v(8em)

#align(right)[Группа: P3316]
#align(right)[Выполнили:]
#align(right)[Сиразетдинов, Шпинева]
#align(right)[Проверил:]
#align(right)[Николаев В.В.]

#v(8em)

#align(center)[г. Санкт-Петербург]
#align(center)[2025]

#pagebreak()

= Задание

Работа рассчитана на двух человек и выполняется в три этапа: настройка, симуляция и обработка сбоя, восстановление.

== Требования к выполнению работы

- В качестве хостов использовать одинаковые виртуальные машины.

- В первую очередь необходимо обеспечить сетевую связность между ВМ.

- Для подключения к СУБД (например, через psql), использовать отдельную виртуальную или физическую машину.

- Демонстрировать наполнение базы и доступ на запись на примере не менее, чем двух таблиц, столбцов, строк, транзакций и клиентских сессий.

== Этап 1. Конфигурация
Развернуть postgres на двух узлах в режиме потоковой репликации. Не использовать дополнительные пакеты. Продемонстрировать доступ в режиме чтение/запись на основном сервере. Продемонстрировать, что новые данные синхронизируются на резервный сервер.

== Этап 2. Симуляция и обработка сбоя
=== 2.1 Подготовка:

- Установить несколько клиентских подключений к СУБД.

- Продемонстрировать состояние данных и работу клиентов в режиме чтение/запись.

=== 2.2 Сбой:

- Симулировать ошибку диска на основном узле - удалить директорию PGDATA со всем содержимым.

=== 2.3 Обработка:

- Найти и продемонстрировать в логах релевантные сообщения об ошибках.

- Выполнить переключение (failover) на резервный сервер.

- Продемонстрировать состояние данных и работу клиентов в режиме чтение/запись.

== Восстановление
- Восстановить работу основного узла - откатить действие, выполненное с виртуальной машиной на этапе 2.2.

- Актуализировать состояние базы на основном узле - накатить все изменения данных, выполненные на этапе 2.3.

- Восстановить исправную работу узлов в исходной конфигурации (в соответствии с этапом 1).

- Продемонстрировать состояние данных и работу клиентов в режиме чтение/запись.

#pagebreak()

= Создание виртуальных машин

1) Арендуем на яндекс клауде две виртуальные машины

#image("./img/vm.png")

#image("./img/vm_2.png")

2) Настроим ssh config
```
Host rshd-1
	HostName 62.84.113.222
	User rshd
	Port 22
	IdentityFile ~/.ssh/ssh-key-1747436533579

Host rshd-2
	HostName 62.84.113.181
	User rshd
	Port 22
	IdentityFile ~/.ssh/ssh-key-1747436533579
```

3) Проверим подключение

#image("img/connection.png")

4) Установим postgresql

Для этого исполним команду

```sh
sudo apt install postgresql postgresql-contrib
```

#pagebreak()

= Настроим репликацию

== Настройка мастера

```sh
sudo -i -u postgres
```

С помощью команды `createuser --replication -P rep_user` создадим пользователя rep_user с паролем `password`
и разрешением на репликацию

Узнаем расположение конфигурационного файла

#image("img/config_file.png")

Добавим в конфигурационный файл следующие строки

```conf
archive_mode = on
archive_command = 'cp %p /oracle/pg_data/archive/%f'
max_wal_senders = 10
wal_level = replica
wal_log_hints = on
```

Добавим в pg_hba.conf информацию для подключения юзера репликации

```conf
host    replication     rep_user        10.128.0.12/32          scram-sha-256
```

И в заверешение перезагрузим сервер

#image("img/master_restart.png")

#image("img/master_logs.png")

== Настройка слейва

```sh
sudo -i -u postgres
```

Внесем в postgresql.conf

```conf
listen_addresses = 'localhost, 10.128.0.12'
```

Остановим сервер

```sh
systemctl stop postgresql
```

Удалим файлы из каталога main

```sh
rm -rf /var/lib/postgresql/16/main/*
```

Проведем проверку репликации. Для этого исполним команду

```sh
pg_basebackup -R -h 10.128.0.29 -U rep_user -D /var/lib/postgresql/16/main -P
systemctl start postgresql
```

- флаг -R означает создание файла *standby.signal*, который означает, что сервер - реплика

#image("img/basebackup.png")


== Подготовка

=== Мастер

```sh
psql -c 'select client_addr, state from pg_stat_replication;'
```

#image("img/check_master.png")

=== Слейв

```sh
psql -c 'select sender_host, status from pg_stat_wal_receiver;'
```

#image("img/check_slave.png")

== Наполнение данными

На мастере подключимся с помощью команды `psql`

```sql
start transaction;
create table rshd_user(
    id serial primary key,
    name text not null,
    lab int not null
);
insert into rshd_user (name, lab) values
    ('Ульяна', 4),
    ('Азат', 4)
;
commit;
```

На локальном компьютере с помощью команды `psql -h 62.84.113.222 -d postgres -U rshd`

```sql
start transaction;
create table rshd_lab(
    id serial primary key,
    name text not null,
    status boolean not null
);
insert into rshd_lab (name, status) values
    ('Лаб1', true),
    ('Лаб2', true),
    ('Лаб3', true),
    ('Лаб4', false)
;
commit;
```

На слейве проверим что данные добавились

```sql
select * from rshd_user;
select * from rshd_lab;
```

#image("img/show_data_replica.png")

Теперь проверим что слейв работает в режиме read_only

```sql
create table test (id int);
```

#image("img/create_data_replica.png")

#pagebreak()

= Сбой

Исполним команду на мастере

```sh
mv  /var/lib/postgresql/16/main ~/main_save
```

Посмотрим логи:

#image("img/fail_logs.png")

Выполним failover с помощью команды

```sh
/usr/lib/postgresql/16/bin/pg_ctl promote -D /var/lib/postgresql/16/main
```
Команда переключает реплику в режим read_write

#image("img/fail_promote_log.png")

Добавим данные на слейве

```sql
insert into rshd_user (name, lab) values
    ('Ульяна', 3),
    ('Азат', 3)
;
```

Теперь наш слейв сервер стал мастером

#pagebreak()

= Восстановление

Чтобы восстановить данные на мастере нужно заново сделать pg_basebackup только теперь с слейва на мастер (и без флага -R)

```sh
pg_basebackup -h 10.128.0.12 -U rep_user -D /var/lib/postgresql/16/main -P
```

На слейве создадим *standby.signal* чтобы просигнализировать что он снова слейв

```sh
touch ~/16/main/standby.signal
systemctl restart postgresql
```

На мастере запустим сервер

```sh
systemctl restart postgresql
```

Проверим успешное подключение слейва к мастеру

#image("img/master_slave_after_restore.png")

Добавим новые данные на мастере и покажем что они есть на слейве

```sql
update rshd_lab
set status=false
where name='Лаб4';
```

Проверим что данные синхронизировались

#image("img/master_slave_data_after_restore.png")


#pagebreak

= Вывод

В лабораторой работе мы познакомились с конфигурацией потоковой репликации в БД postgresql и научились переключать
мастер