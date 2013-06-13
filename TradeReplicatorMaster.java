/* TradeReplicatorMaster.java                                                      *
 * v1.2                                                                            *
 * Distributed under the BSD license (http://opensource.org/licenses/BSD-2-Clause) *
 * Copyright (c) 2013, Rostislav Kuratch                                           *
 * All rights reserved.                                                            */


package jforex;

import com.dukascopy.api.*;
import com.dukascopy.api.IAccount;
import com.dukascopy.api.IBar;
import com.dukascopy.api.IConsole;
import com.dukascopy.api.IContext;
import com.dukascopy.api.IEngine;
import com.dukascopy.api.IHistory;
import com.dukascopy.api.IIndicators;
import com.dukascopy.api.IMessage;
import com.dukascopy.api.IStrategy;
import com.dukascopy.api.ITick;
import com.dukascopy.api.IUserInterface;
import com.dukascopy.api.Instrument;
import com.dukascopy.api.JFException;
import com.dukascopy.api.Period;
import com.dukascopy.api.IReportService;

import java.io.PrintStream;
import java.util.*;
import java.net.URL;
import java.net.URLClassLoader;
import java.sql.DriverManager;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Statement;
import java.text.SimpleDateFormat;

@RequiresFullAccess
@Library("postgresql-9.2-1002.jdbc4.jar")

public class TradeReplicatorMaster implements IStrategy {
    
    public class DB_Trade
    {
        public class General_Exception extends Exception
        {
            private String description;
            public General_Exception(String s)
            {
                description = s;
            }

            public String toString()
            {
                return description;
            }
        }
        
        public String master_id;
        public String instrument;
        public int direction;
        public double volume;
        public double open_price;
        public Date open_time;
        public Date close_time;
        public double close_price;
        public String trade_id;
        public double stop_loss;
        public double take_profit;
        public double commission;
        public double profit;
        public double swaps;
        
        public DB_Trade(ResultSet rs) throws SQLException, General_Exception
        {
            ResultSetMetaData meta = rs.getMetaData();
            int cols = meta.getColumnCount();
            if (cols != 14)
                throw new General_Exception("Unexpected number of columns in master trades table, check your DB schema.");
            
            master_id = rs.getString(1);
            instrument = rs.getString(2);
            direction = rs.getInt(3);
            volume = rs.getDouble(4);
            open_price = rs.getDouble(5);
            open_time = rs.getDate(6);
            close_time = rs.getDate(7);
            close_price = rs.getDouble(8);
            trade_id = rs.getString(9);
            stop_loss = rs.getDouble(10);
            take_profit = rs.getDouble(11);
            commission = rs.getDouble(12);
            profit = rs.getDouble(13);
            swaps = rs.getDouble(14);
        }
        
        public String toString()
        {
            String res = "";
            
            SimpleDateFormat date = new SimpleDateFormat("yyyy-MM-DD hh:mm:ss.SSSZ");
            
            try
            {
                if (open_time == null)
                    open_time = date.parse("1970-01-01 00:00:00.000+0000");
                    
                if (close_time == null)
                    close_time = date.parse("1970-01-01 00:00:00.000+0000");
            }
            catch (Exception e)
            {
                console.getOut().println("ERROR:" + e.toString());
                return "";
            }

            res = "master_id=" + master_id + " instrument=" + instrument + " direction=" + direction + " volume=" + volume +
                  " open_price=" + open_price + " open_time=" + date.format(open_time) + " close_time=" + date.format(close_time) + " close_price=" + close_price +
                  " trade_id=" + trade_id + " stop_loss=" + stop_loss + " take_profit=" + take_profit + " commission=" + commission + " profit=" + profit + " swaps=" + swaps;

            return res;
        }
    }

    @Configurable("DB IP/host")
    public String db_ip_setting = "x.x.x.x";
    @Configurable("DB port")
    public String db_port_setting = "5432";
    @Configurable("DB login")
    public String db_user_setting = "db_login";
    @Configurable("DB password")
    public String db_password_setting = "db_pass";
    @Configurable("DB name")
    public String db_name_setting = "db_name";
    @Configurable("Time zone")
    public String timezone_setting = "+03"; //server time zone - ask your broker for the correct value
                                            //if broker obeys daylight savings
                                            //you have to change this setting manually when dst is in effect
                                            //format should be like this (offset in numerical form): +00 (meaning GMT, +01 = GMT+1, etc.)
    @Configurable("Master ID")
    public String master_id_setting = "master_id"; //20 symbols recommended id, use some passwords generator to obtain it
    @Configurable("Deposit currency")
    public String deposit_currency_setting = "USD";

    private IEngine engine;
    private IConsole console;
    private IHistory history;
    private IContext context;
    private IIndicators indicators;
    private IUserInterface userInterface;
    private IReportService report;
    private long prev_time_;
    private Connection db_conn_ = null;

    private void printout_classpath()
    {
 
        ClassLoader cl = ClassLoader.getSystemClassLoader();
 
        URL[] urls = ((URLClassLoader)cl).getURLs();
 
        for(URL url: urls)
        {
            console.getOut().println(url.getFile());
        }
    }

    void create_db_stucture()
    {
        try
        {
            Statement query = db_conn_.createStatement();

            String create_query = "CREATE TABLE masters(master_id character varying(25) NOT NULL, deposit_currency character varying(10) NOT NULL, CONSTRAINT masters_pkey PRIMARY KEY (master_id)) WITH (OIDS=FALSE);";
            query.executeQuery(create_query);
            
            create_query = "CREATE TABLE slaves(slave_id character varying(25) NOT NULL, deposit_currency character varying(10) NOT NULL, CONSTRAINT slaves_pkey PRIMARY KEY (slave_id)) WITH (OIDS=FALSE);";
            query.executeQuery(create_query);

            create_query = "CREATE TABLE master_trades(master_id character varying(25) NOT NULL, instrument character varying(12) NOT NULL, direction integer NOT NULL,";
            String query_part2 = " volume numeric(10,5) NOT NULL, open_price numeric(10,5) NOT NULL, open_time timestamp with time zone NOT NULL, close_time timestamp with time zone,";
            String query_part3 = " close_price numeric(10,5) DEFAULT NULL::numeric, trade_id character varying(25) NOT NULL, stop_loss numeric(10,5) DEFAULT NULL::numeric,";
            String query_part4 = " take_profit numeric(10,5) DEFAULT NULL::numeric,";
            String query_part8 = " commission numeric(10,5) DEFAULT NULL::numeric, profit numeric(10,5) DEFAULT NULL::numeric, swaps numeric(10,5) DEFAULT NULL::numeric";
            String query_part5 = ", CONSTRAINT master_trades_pkey PRIMARY KEY (master_id, trade_id), CONSTRAINT master_trades_master_id_fkey FOREIGN KEY (master_id) REFERENCES masters (master_id) MATCH SIMPLE ON UPDATE NO ACTION ON DELETE NO ACTION) WITH (OIDS=FALSE);";
            query.executeQuery(create_query);

            create_query = "CREATE TABLE slave_trades(master_id character varying(25) NOT NULL, instrument character varying(12) NOT NULL, direction integer NOT NULL,";
            query_part2 = " volume numeric(10,5) NOT NULL, open_price numeric(10,5) NOT NULL, open_time timestamp with time zone NOT NULL, close_time timestamp with time zone,";
            query_part3 = " close_price numeric(10,5) DEFAULT NULL::numeric, master_trade_id character varying(25) NOT NULL, stop_loss numeric(10,5) DEFAULT NULL::numeric,";
            query_part4 = " take_profit numeric(10,5) DEFAULT NULL::numeric, slave_id character varying(25) NOT NULL, slave_trade_id character varying(25) NOT NULL,";
            query_part8 = " commission numeric(10,5) DEFAULT NULL::numeric, profit numeric(10,5) DEFAULT NULL::numeric, swaps numeric(10,5) DEFAULT NULL::numeric, status text";
            query_part5 = ", CONSTRAINT slave_trades_pkey PRIMARY KEY (slave_id, slave_trade_id), CONSTRAINT slave_trades_master_id_fkey FOREIGN KEY (master_id) REFERENCES masters (master_id) MATCH SIMPLE ON UPDATE NO ACTION ON DELETE NO ACTION";
            String query_part6 = ", CONSTRAINT slave_trades_master_id_fkey1 FOREIGN KEY (master_id, master_trade_id) REFERENCES master_trades (master_id, trade_id) MATCH SIMPLE ON UPDATE NO ACTION ON DELETE NO ACTION";
            String query_part7 = ", CONSTRAINT slave_trades_slave_id_fkey FOREIGN KEY (slave_id) REFERENCES slaves (slave_id) MATCH SIMPLE ON UPDATE NO ACTION ON DELETE NO ACTION) WITH (OIDS=FALSE);";
            query.executeQuery(create_query);

            String insert_master = "INSERT INTO masters VALUES ('" + master_id_setting + "', '" + deposit_currency_setting + "');";
            query.executeQuery(insert_master);
        }
        catch (SQLException e)
        {
            console.getOut().println("ERROR: " + e.toString());
            return;
        }
    }

    private Connection db_connect(String db_name, String host, String port, String user, String pass)
    {
        console.getOut().println("-------- PostgreSQL JDBC Connection Testing ------------");
        try
        {
            Class.forName("org.postgresql.Driver");
        }
        catch (ClassNotFoundException e)
        {
            console.getOut().println("Where is your PostgreSQL JDBC Driver? Download/include in your library path!");
            return null;
        }
        
        console.getOut().println("PostgreSQL JDBC Driver Registered!");
        
        Connection connection = null;
        
        try
        {
            connection = DriverManager.getConnection("jdbc:postgresql://" + host + ":" + port + "/" + db_name, user, pass);
        }
        catch (SQLException e)
        {
            console.getOut().println("DB connection failed!");
            return null;
        }
        
        if (connection != null)
        {
            console.getOut().println("DB connection established!");
        }
        else
        {
            console.getOut().println("Failed to make a connection!");
        }
        
        return connection;
    }
    
    private void print_result_set(ResultSet rs) throws SQLException
    {
        ResultSetMetaData meta = rs.getMetaData();
        int cols = meta.getColumnCount();
        
        rs.last();
        int rows = rs.getRow();
        rs.beforeFirst();
        
        for (int i = 0; i < rows; ++i)
        {
            rs.next();
            String row = "";
            for (int j = 1; j <= cols; ++j)
            {
                String col = meta.getColumnName(j) + " : " + rs.getString(j) + ", ";
                row += col;
            }

            console.getOut().println(row);
        }
    }
    
    private ArrayList<DB_Trade> get_open_trades_from_db()
    {
        //console.getOut().println("--> get_open_trades_from_db");
        ArrayList<DB_Trade> open_trades = new ArrayList<DB_Trade>();

        try
        {
            Statement query = db_conn_.createStatement(ResultSet.TYPE_SCROLL_INSENSITIVE, ResultSet.CONCUR_READ_ONLY);
            ResultSet rs = query.executeQuery("SELECT * FROM master_trades WHERE close_time IS NULL AND master_id = '" + master_id_setting + "';");
            
            //print_result_set(rs);
            
            rs.last();
            int rows = rs.getRow();
            rs.beforeFirst();
            
            for (int i = 0; i < rows; ++i)
            {
                rs.next();            
                DB_Trade open_trade = new DB_Trade(rs);
                open_trades.add(open_trade);
                
                //console.getOut().println("trade#" + i + " = " + open_trade);
            }
        }
        catch (SQLException e)
        {
            console.getOut().println("ERROR: " + e.toString());
            return open_trades;
        }
        catch (DB_Trade.General_Exception e)
        {
            console.getOut().println("ERROR: " + e.toString());
            return open_trades;
        }

        //console.getOut().println("<-- get_open_trades_from_db");
        return open_trades;
    }
            
    public void onStart(IContext context) throws JFException {
        this.engine = context.getEngine();
        this.console = context.getConsole();
        this.history = context.getHistory();
        this.context = context;
        this.indicators = context.getIndicators();
        this.userInterface = context.getUserInterface();
        this.report = context.getReportService();
        
        prev_time_ = 0;        
        db_conn_ = db_connect(db_name_setting, db_ip_setting, db_port_setting, db_user_setting, db_password_setting);
        create_db_stucture();
    }
    
    public void onAccount(IAccount account) throws JFException 
    {
    }

    public void onMessage(IMessage message) throws JFException
    {
    }

    public void onStop() throws JFException
    {
        try
        {
            if (db_conn_ != null)
                db_conn_.close();
        }
        catch (SQLException e)
        {
            console.getOut().println("DB connection failed to close!");
            return;
        }
    }

    private IOrder is_trade_closed(String id) throws JFException
    {
        //console.getOut().println("--> is_trade_closed");
        
        IOrder order = history.getHistoricalOrderById(id);
        if (order != null)
        {
            if (order.getClosePrice() != 0)
            {
                //console.getOut().println("pos.id =  " + order.getId() + "close_time = " + order.getCloseTime() + " close_price = " + order.getClosePrice());
                //console.getOut().println("<-- is_trade_closed result non-null");
                return order;
            }
        }

        //console.getOut().println("<-- is_trade_closed result null");
        return null;
    }

    private void on_trade_close(IOrder closed_order) throws JFException
    {
        //console.getOut().println("--> on_trade_close");
        if (closed_order == null)
            return;

        String master_id = master_id_setting;
        double close_price = closed_order.getClosePrice();
        SimpleDateFormat date_format = new SimpleDateFormat("yyyy-MM-dd hh:mm:ss.SSSZ");
        Date current = new Date();
        String close_time = date_format.format(current);
        String trade_id = closed_order.getId();
        double stop_loss = closed_order.getStopLossPrice();
        double take_profit = closed_order.getTakeProfitPrice();
        double profit = closed_order.getProfitLossInAccountCurrency();
        double swaps = 0;

        String update_query = "UPDATE master_trades SET stop_loss=" + stop_loss + ", take_profit=" + take_profit + ", close_time='" + close_time + "', close_price=" + close_price + ", profit=" + profit + ", swaps=" + swaps + " WHERE (master_id='" + master_id + "') AND (trade_id='" + trade_id + "');";
        console.getOut().println("Master closed trade: " + update_query);

        try
        {
            Statement query = db_conn_.createStatement();
            query.executeQuery(update_query);        
        }
        catch (SQLException e)
        {
            console.getOut().println("ERROR: " + e.toString());
            return;
        }
        
        //console.getOut().println("<-- on_trade_close");
    }
    
    private void find_closed_trades(ArrayList<DB_Trade> trades) throws JFException
    {
        //console.getOut().println("--> find_closed_trades");
        for (DB_Trade trade : trades)
        {
            on_trade_close(is_trade_closed(trade.trade_id));
        }
        //console.getOut().println("<-- find_closed_trades");
    }

    private void on_new_trade(IOrder order)
    {
        //console.getOut().println("--> on_new_trade");
        String master_id = master_id_setting;
        String instrument = order.getInstrument().toString();
        instrument = instrument.replace("/", "");
        instrument = instrument.replace("\\", "");
        
        int direction = 0;
        if (!order.isLong()) direction = 1;

        double volume = order.getAmount() * 10; //convert into mt4 lots (from fractions of million to fractions of 100K)
        double open_price = order.getOpenPrice();
        
        SimpleDateFormat date_format = new SimpleDateFormat("yyyy-MM-dd hh:mm:ss.SSSZ");
        Date current = new Date();
        String open_time = date_format.format(current);
        
        String trade_id = order.getId();
        double stop_loss = order.getStopLossPrice();
        double take_profit = order.getTakeProfitPrice();
        
        double com = order.getCommission();
        String commission = "" + com;
        
        String insert_query = "INSERT INTO master_trades VALUES ('" + master_id + "', '" + instrument + "', " + direction + ", " + volume + ", " + open_price + ", '" + open_time + "', NULL, NULL, '" + trade_id + "', " + stop_loss + ", " + take_profit + ", " + commission + ");";
        console.getOut().println("Master opened a new trade: " + insert_query);
        
        try
        {
            Statement query = db_conn_.createStatement();
            query.executeQuery(insert_query);        
        }
        catch (SQLException e)
        {
            console.getOut().println("ERROR: " + e.toString());
            return;
        }
        
        //console.getOut().println("<-- on_new_trade");
    }

    private void find_new_trades(ArrayList<DB_Trade> trades) throws JFException
    {
        //console.getOut().println("--> find_new_trades");
        List<IOrder> orders = engine.getOrders();
        for (IOrder order : orders)
        {
            if (order.getState() != IOrder.State.FILLED)
                continue;

            Boolean found = false;
            for (DB_Trade trade : trades)
            {
                String pos_id = order.getId();
                pos_id.trim();
                trade.trade_id.trim();

                //console.getOut().println("trade_id = " + trade.trade_id + ", pos id = " + pos_id);
                if (trade.trade_id.equals(pos_id))
                {
                    found = true;
                    break;
                }
            }

            if (!found)
                on_new_trade(order);
        }
        
        //console.getOut().println("<-- find_new_trades");
    }

    private void onTime(long time) throws JFException
    {
        //console.getOut().println("--> onTime");
        try
        {
            ArrayList<DB_Trade> trades = get_open_trades_from_db();
            find_closed_trades(trades);
            
            trades = get_open_trades_from_db();
            find_new_trades(trades);
        }
        catch (Exception e)
        {
            console.getOut().println(e);
            return;
        }
        //console.getOut().println("<-- onTime");
    }

    public void onTick(Instrument instrument, ITick tick) throws JFException 
    {
        long cur_time = tick.getTime();
        if (cur_time - prev_time_ >= 1000)
        {
            prev_time_ = cur_time;
            onTime(cur_time);
        }
    }
    
    public void onBar(Instrument instrument, Period period, IBar askBar, IBar bidBar) throws JFException
    {
    }
}