/* Trade Replicator (Master).mq4                                                   *
 * v1.2                                                                            *
 * Distributed under the BSD license (http://opensource.org/licenses/BSD-2-Clause) *
 * Copyright (c) 2013, Rostislav Kuratch                                           *
 * All rights reserved.                                                            */

#property copyright "Copyright 2013, Rostislav Kuratch"
#property link      "Rostislav.Kuratch@gmail.com"
#property show_inputs

extern string g_db_ip_setting = "your_db_ip";
extern string g_db_port_setting = "5432";
extern string g_db_user_setting = "your_db_user_with_rw_permissions";
extern string g_db_password_setting = "your_db_user_password";
extern string g_db_name_setting = "your_db_name";

extern string g_timezone_setting = "your_broker_time_zone"; //server time zone - ask your broker for the correct value
                                                            //if broker obeys daylight savings
                                                            //you have to change this setting manually when dst is in effect
                                                            //format should be like this (offset in numerical form): +00 (meaning GMT, +01 = GMT+1, etc.)

extern string g_master_id_setting = "your_randomly_generated_master_id"; //20 symbols recommended id, use some passwords generator to obtain it
extern string g_deposit_currency = "USD";

#include <postgremql4.mqh>

bool SplitString(string stringValue, string separatorSymbol, string& results[], int expectedResultCount = 0)
{
   if (StringFind(stringValue, separatorSymbol) < 0)
   {// No separators found, the entire string is the result.
      ArrayResize(results, 1);
      results[0] = stringValue;
   }
   else
   {   
      int separatorPos = 0;
      int newSeparatorPos = 0;
      int size = 0;

      while(newSeparatorPos > -1)
      {
         size = size + 1;
         newSeparatorPos = StringFind(stringValue, separatorSymbol, separatorPos);
         
         ArrayResize(results, size);
         if (newSeparatorPos > -1)
         {
            if (newSeparatorPos - separatorPos > 0)
            {  // Evade filling empty positions, since 0 size is considered by the StringSubstr as entire string to the end.
               results[size-1] = StringSubstr(stringValue, separatorPos, newSeparatorPos - separatorPos);
            }
         }
         else
         {  // Reached final element.
            results[size-1] = StringSubstr(stringValue, separatorPos, 0);
         }
         
         
         //Alert(results[size-1]);
         separatorPos = newSeparatorPos + 1;
      }
   }   
   
   if (expectedResultCount == 0 || expectedResultCount == ArraySize(results))
   {  // Results OK.
      return (true);
   }
   else
   {  // Results are WRONG.
      Print("ERROR - size of parsed string not expected.", true);
      return (false);
   }
}

bool is_error(string str)
{
    return (StringFind(str, "error") != -1);
}

bool connect_db()
{
    string res = pmql_connect(g_db_ip_setting, g_db_port_setting, g_db_user_setting, g_db_password_setting, g_db_name_setting);
    if ((res != "ok") && (res != "already connected"))
    {
        Print("DB not connected!");
        return (false);
    }
 
    return(true);
}

void create_db_stucture()
{
    string create_query = "CREATE TABLE masters(master_id character varying(25) NOT NULL, deposit_currency character varying(10) NOT NULL, CONSTRAINT masters_pkey PRIMARY KEY (master_id)) WITH (OIDS=FALSE);";
    string res = pmql_exec(create_query);

    if (is_error(res))
        Print(res);
        
    create_query = "CREATE TABLE slaves(slave_id character varying(25) NOT NULL, deposit_currency character varying(10) NOT NULL, CONSTRAINT slaves_pkey PRIMARY KEY (slave_id)) WITH (OIDS=FALSE);";
    res = pmql_exec(create_query);

    if (is_error(res))
        Print(res);

    create_query = "CREATE TABLE master_trades(master_id character varying(25) NOT NULL, instrument character varying(12) NOT NULL, direction integer NOT NULL,";
    string query_part2 = " volume numeric(10,5) NOT NULL, open_price numeric(10,5) NOT NULL, open_time timestamp with time zone NOT NULL, close_time timestamp with time zone,";
    string query_part3 = " close_price numeric(10,5) DEFAULT NULL::numeric, trade_id character varying(25) NOT NULL, stop_loss numeric(10,5) DEFAULT NULL::numeric,";
    string query_part4 = " take_profit numeric(10,5) DEFAULT NULL::numeric,";
    string query_part8 = " commission numeric(10,5) DEFAULT NULL::numeric, profit numeric(10,5) DEFAULT NULL::numeric, swaps numeric(10,5) DEFAULT NULL::numeric";
    string query_part5 = ", CONSTRAINT master_trades_pkey PRIMARY KEY (master_id, trade_id), CONSTRAINT master_trades_master_id_fkey FOREIGN KEY (master_id) REFERENCES masters (master_id) MATCH SIMPLE ON UPDATE NO ACTION ON DELETE NO ACTION) WITH (OIDS=FALSE);";
    res = pmql_exec(create_query + query_part2 + query_part3 + query_part4 + query_part8 + query_part5);

    if (is_error(res))
        Print(res);

    create_query = "CREATE TABLE slave_trades(master_id character varying(25) NOT NULL, instrument character varying(12) NOT NULL, direction integer NOT NULL,";
    query_part2 = " volume numeric(10,5) NOT NULL, open_price numeric(10,5) NOT NULL, open_time timestamp with time zone NOT NULL, close_time timestamp with time zone,";
    query_part3 = " close_price numeric(10,5) DEFAULT NULL::numeric, master_trade_id character varying(25) NOT NULL, stop_loss numeric(10,5) DEFAULT NULL::numeric,";
    query_part4 = " take_profit numeric(10,5) DEFAULT NULL::numeric, slave_id character varying(25) NOT NULL, slave_trade_id character varying(25) NOT NULL,";
    query_part8 = " commission numeric(10,5) DEFAULT NULL::numeric, profit numeric(10,5) DEFAULT NULL::numeric, swaps numeric(10,5) DEFAULT NULL::numeric, status text";
    query_part5 = ", CONSTRAINT slave_trades_pkey PRIMARY KEY (slave_id, slave_trade_id), CONSTRAINT slave_trades_master_id_fkey FOREIGN KEY (master_id) REFERENCES masters (master_id) MATCH SIMPLE ON UPDATE NO ACTION ON DELETE NO ACTION";
    string query_part6 = ", CONSTRAINT slave_trades_master_id_fkey1 FOREIGN KEY (master_id, master_trade_id) REFERENCES master_trades (master_id, trade_id) MATCH SIMPLE ON UPDATE NO ACTION ON DELETE NO ACTION";
    string query_part7 = ", CONSTRAINT slave_trades_slave_id_fkey FOREIGN KEY (slave_id) REFERENCES slaves (slave_id) MATCH SIMPLE ON UPDATE NO ACTION ON DELETE NO ACTION) WITH (OIDS=FALSE);";
    res = pmql_exec(create_query + query_part2 + query_part3 + query_part4 + query_part8 + query_part5 + query_part6 + query_part7);

    if (is_error(res))
        Print(res);
        
    string insert_master = "INSERT INTO masters VALUES ('" + g_master_id_setting + "', '" + g_deposit_currency + "');";
    res = pmql_exec(insert_master);
    
    if (is_error(res))
        Print(res);
}

int g_trade_ids[];
string g_trades[];

bool reconnect()
{
    pmql_disconnect();
    return (connect_db());
}

int row_count(string& query_result)
{
    int res = 0;

    string query_res = query_result;    
    int len = StringLen(query_res);

    if (len == 0)
        return (0);

    for (int i = 0; i < len; i++)
    {
        if (StringGetChar(query_res, i) == '*')
            res++;
    }

    return (res + 1);
}

void trades_from_rows(string& rows)
{
    int trades_count = row_count(rows);

    ArrayResize(g_trade_ids, trades_count);
    ArrayResize(g_trades, trades_count);

    if (trades_count == 0)
        return;

    SplitString(rows, "*", g_trades);

    int tokens_count = ArraySize(g_trades);
    if (tokens_count != trades_count)
    {
        Print("ERROR: tokens_count = ", tokens_count, ", trades_count = ", trades_count);
        return;
    }

    for (int i = 0; i < trades_count; i++)
    {
        string trade_tokens[];
        SplitString(g_trades[i], "|", trade_tokens);
        
        if (ArraySize(trade_tokens) < 9)
        {
            Print("ERROR: ArraySize(trade_tokens) = ", ArraySize(trade_tokens));
            return;
        }
        
        string value_tokens[];
        SplitString(trade_tokens[8], "=", value_tokens);
        
        if (ArraySize(value_tokens) < 2)
        {
            Print("ERROR: ArraySize(value_tokens) = ", ArraySize(value_tokens));
            return;
        }
        
        g_trade_ids[i] = StrToInteger(value_tokens[1]);
    }
}

void get_open_trades_from_db()
{
    if (!connect_db())
        return;

    string query = "SELECT * FROM master_trades WHERE close_time IS NULL AND master_id = '" + g_master_id_setting + "';";
    string query_res = pmql_exec(query);
    
    if (is_error(query_res))
    {
        Print(query_res);
        reconnect();
        return;
    }

    trades_from_rows(query_res);
}

bool is_trade_closed(int order)
{
    return (OrderSelect(order, SELECT_BY_TICKET, MODE_HISTORY) && (OrderCloseTime() > 1000000000));
}

//trade close event to DB
void on_trade_close(int order)
{
    Print("Writing trade close to DB for order #" + order);

    if (!OrderSelect(order, SELECT_BY_TICKET, MODE_HISTORY))
    {
        Print("ERROR: cannot select order ", order);
        return;
    }

    string master_id = g_master_id_setting;
    double close_price = OrderClosePrice();
    string close_time = create_db_timestamp(OrderCloseTime());
    int trade_id = OrderTicket();
    double stop_loss = OrderStopLoss();
    double take_profit = OrderTakeProfit();
    double profit = OrderProfit();
    double swaps = OrderSwap();

    string update_query = "UPDATE master_trades SET stop_loss=" + DoubleToStr(stop_loss, 5) + ", take_profit=" + DoubleToStr(take_profit, 5) + ", close_time='" + close_time + "', close_price=" + DoubleToStr(close_price, 5) + ", profit=" + DoubleToStr(profit, 5) + ", swaps=" + DoubleToStr(swaps, 5) + " WHERE (master_id='" + master_id + "') AND (trade_id='" + trade_id + "');";
    string res = pmql_exec(update_query);

    if (is_error(res))
    {
        Print(res);
        reconnect();
    }
}

//check all g_trade_ids and find closed, for each closed call on_trade_close() once
void find_closed_trades()
{
    int total_trades = ArraySize(g_trade_ids);
    for (int i = 0; i < total_trades; i++)
    {
        if (is_trade_closed(g_trade_ids[i]))
            on_trade_close(g_trade_ids[i]);
    }
}

string create_db_timestamp(datetime timestamp)
{
    string time = TimeToStr(timestamp, TIME_DATE | TIME_SECONDS);
    time = StringSetChar(time, 4, '-');
    time = StringSetChar(time, 7, '-');

    time = time + " " + g_timezone_setting;

    Print("Time = " + time);
    return (time);
}

//trade open event to DB
void on_trade_open(int order)
{
    Print("Writing trade open to DB for order #" + order);
    
    if (!OrderSelect(order, SELECT_BY_TICKET, MODE_TRADES))
    {
        Print("ERROR: cannot select order ", order);
        return;
    }

    string master_id = g_master_id_setting;
    string instrument = OrderSymbol();
    int direction = OrderType();
    double volume = OrderLots();
    double open_price = OrderOpenPrice();
    string open_time = create_db_timestamp(OrderOpenTime());
    int trade_id = OrderTicket();
    double stop_loss = OrderStopLoss();
    double take_profit = OrderTakeProfit();
    double commission = OrderCommission();
    
    string insert_query = "INSERT INTO master_trades VALUES ('" + master_id + "', '" + instrument + "', " + direction + ", " + DoubleToStr(volume, 5) + ", " + DoubleToStr(open_price, 5) + ", '" + open_time + "', NULL, NULL, '" + trade_id + "', " + DoubleToStr(stop_loss, 5) + ", " + DoubleToStr(take_profit, 5)+ ", " + DoubleToStr(commission, 5) + ");";
    string res = pmql_exec(insert_query);

    if (is_error(res))
    {
        Print(res);
        reconnect();
    }
}

bool is_open_in_db(int trade_id)
{
    int total_trades = ArraySize(g_trade_ids);
    for (int i = 0; i < total_trades; i++)
    {
        if (trade_id == g_trade_ids[i])
            return (true);
    }

    return (false);
}

void find_new_trades()
{
    int total = OrdersTotal();

    for (int pos = 0; pos < total; pos++)
    {
        if (OrderSelect(pos, SELECT_BY_POS) == false) continue;

        if (OrderType() < 2)
        {
            if (!is_open_in_db(OrderTicket()))
                on_trade_open(OrderTicket());
        }
    }
}

int start()
{
    if (!connect_db())
        return (-1);

    create_db_stucture();

    datetime prev_time = TimeLocal();

    while (true)
    {
        if ((TimeLocal() - prev_time) >= 1) //Do stuff once per second
        {
            prev_time = TimeLocal();
            
            get_open_trades_from_db();
            find_closed_trades();

            get_open_trades_from_db();
            find_new_trades();
        }

        Sleep(500);
    }

    pmql_disconnect();
    return(0);
}
