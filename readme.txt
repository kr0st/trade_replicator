Trade Replicator enables you to copy trades between separate accounts, possibly located
at different brokerages. Trades are copied from “master” account to a number of “slave”
accounts, volume scaling and trade direction inversion are supported on slave side.

Trades are copied via database, so Trade Replicator scripts both master and slave
versions use PostgreMQL4 to communicate with the database server,
currently only PostgreSQL server is supported.

Why you might want to try this?

    * you are a successful trader and would like to offer signal providing service so
      your clients could subscribe to your trading for a monthly fee and you do not
      want to do this via Zulu or eToro for your own reasons;

    * you are a very consistent Forex looser wishing to use trade inversion
      in order to turn your loosing trades on one account into the winning trades
      on another account.

Some remarks to the above proposals: in the first case your client base should be
rather small and you have to give each person a different DB user/password to make
it possible to terminate service access for a given client if need be.
For bigger client base it is hardly possible to manage all clients manually.

As for the second case, what I mean by consistent looser is that you have to loose
significantly more than 50% of the trades and loses should be definitely way bigger
than the spread and than your average win.
It turns out that consistent losers are as rare as the consistent winners, so it is more
of a joke but of course you are welcome to try that and see :)


Supported Platforms

Windows XP+ and any version of MT4 terminal running on it.


License

BSD 2-Clause (http://opensource.org/licenses/BSD-2-Clause).


Known issues

Please refer to this section in PostgreMQL4 readme, it applies here too.


Install

First of all you need to have PostgreMQL4 DLLs in all of your master and slave MT4
terminals, this is covered in the “Install” section of PostgreMQL4 readme.
When PostgreMQL4 is deployed you just have to place either “trade_replicator_master.mq4”
or “trade_replicator_slave.mq4” into experts/scripts folder of your MT4 installation
and compile the script.

Master script is used at the signal provider side and slave version is used
at the signal subscriber side.


Important Notes

If you opened some trades and then run the master script it will detect that some
new trades appeared and will write them to DB for further copying to slave accounts.
Your master account should be used only for trading that you want to be copied.

Please note that SL and TP will not be copied, this means master terminal should be
always on with master script running because without it slaves will have no information
about which trades should be closed and which should stay open.

On start script will try to create all needed DB tables, so at least on the first start
you should give script’s DB user rights to create tables.

Many masters and slaves could use the same database as long as the rule of uniqueness
is not violated for master ids and for slave ids.

It is possible to copy from many masters at once but many instances of slave script
should be running, each configured to copy from a specific master id.


How it works

Each master is assigned a random-generated id, when master script is running each trade
that appears on master account will be placed in the database (master_trades table)
identified uniquely by master id and MT4 order ticket.

At client side slave version of the script is running and scanning DB every second
for new master trades and also for trades that have been closed by master.

If new master trade is found it is opened in client MT4 terminal and
is written to DB (slave_trades table) uniquely identified by slave id and
new order ticket. In case trade copy failed, status column will have the error number
that has been reported by the MT4 server. When there is no error status column is NULL.

When master closes the trade it is also going to be closed at the client side and
information in DB will be updated with the time and profit of the closed trade.

This is how it works in short, you are encouraged to view the database schema because
it contains a lot of useful information that can be used to prepare the summary
of trading for masters and slaves.


Quick Start

Before running the scripts they have to be properly configured. You can do it every time
when you run the script or you can write values you need right into mql script file
and compile it.

The first important thing to understand and configure is master and slave ids.
The best way is to use some password generating software and generate 20-symbol ids.
However it should be clear that slave script should contain the existing master id
because slave script will be copying trades only from the master with the given id.

When ids are configured it is time to setup the database access. Parameters are pretty
much self-explanatory, the only thing to remember here is that read/write access is
required both for master and slave scripts.

Please see other parameters in the script file, all of them are easy to understand and
all of them need to be configured properly.


Version History

v1.0
Initial release.