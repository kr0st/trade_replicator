/* Trade Replicator (Slave).mq4                                                    *
 * v1.1                                                                            *
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

extern string g_slave_id_setting = "your_randomly_generated_slave_id"; //20 symbols recommended id, use some passwords generator to obtain it
extern string g_master_id_setting = "id_of_the_master_you_want_to_copy_from";
extern string g_deposit_currency = "USD";
extern int g_max_slippage = 4;
extern bool g_reverse_trades = false; //invert the direction of the master trade or not
extern double g_trade_scale = 1; //volume multiplier, master lots will be multiplied by it and the result used for the copied trade opening

string g_subscribed_masters = "";
string g_current_master_id = "";

void fill_in_subscribed_masters()
{
   g_subscribed_masters = //list of masters in the form "master1" + " master2" + " master3" etc.
}

#include <postgremql4.mqh>
#include <stderror.mqh>

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
        
    string insert_master = "INSERT INTO slaves VALUES ('" + g_slave_id_setting + "', '" + g_deposit_currency + "');";
    res = pmql_exec(insert_master);
    
    if (is_error(res))
        Print(res);
}

string g_trade_instrument[];
int g_trade_direction[];
double g_trade_volume[];
double g_trade_open_price[];
double g_trade_to_close_id[];
string g_trades[];
string g_master_ids[];

int tokenize_masters()
{
    ArrayResize(g_master_ids, 0);
    SplitString(g_subscribed_masters, " ", g_master_ids);
    
    return (ArraySize(g_master_ids));
}

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

bool open_trades_from_rows(string& rows)
{
    int trades_count = row_count(rows);

    ArrayResize(g_trades, trades_count);
    ArrayResize(g_trade_instrument, trades_count);
    ArrayResize(g_trade_direction, trades_count);
    ArrayResize(g_trade_volume, trades_count);
    ArrayResize(g_trade_open_price, trades_count);

    if (trades_count == 0)
        return (false);

    SplitString(rows, "*", g_trades);

    int tokens_count = ArraySize(g_trades);
    if (tokens_count != trades_count)
    {
        Print("ERROR: tokens_count = ", tokens_count, ", trades_count = ", trades_count);
        return (false);
    }

    for (int i = 0; i < trades_count; i++)
    {
        string trade_tokens[];
        SplitString(g_trades[i], "|", trade_tokens);
        
        if (ArraySize(trade_tokens) < 14)
        {
            Print("ERROR: ArraySize(trade_tokens) = ", ArraySize(trade_tokens));
            return (false);
        }
        
        string value_tokens[];
        SplitString(trade_tokens[1], "=", value_tokens);
        
        if (ArraySize(value_tokens) < 2)
        {
            Print("ERROR: ArraySize(value_tokens) = ", ArraySize(value_tokens));
            return (false);
        }
        
        g_trade_instrument[i] = value_tokens[1];
        
        SplitString(trade_tokens[2], "=", value_tokens);
        
        if (ArraySize(value_tokens) < 2)
        {
            Print("ERROR: ArraySize(value_tokens) = ", ArraySize(value_tokens));
            return (false);
        }
        
        g_trade_direction[i] = StrToInteger(value_tokens[1]);

        SplitString(trade_tokens[3], "=", value_tokens);
        
        if (ArraySize(value_tokens) < 2)
        {
            Print("ERROR: ArraySize(value_tokens) = ", ArraySize(value_tokens));
            return (false);
        }
        
        g_trade_volume[i] = StrToDouble(value_tokens[1]);

        SplitString(trade_tokens[4], "=", value_tokens);
        
        if (ArraySize(value_tokens) < 2)
        {
            Print("ERROR: ArraySize(value_tokens) = ", ArraySize(value_tokens));
            return (false);
        }
        
        g_trade_open_price[i] = StrToDouble(value_tokens[1]);
        
        SplitString(trade_tokens[8], "=", value_tokens);
        
        if (ArraySize(value_tokens) < 2)
        {
            Print("ERROR: ArraySize(value_tokens) = ", ArraySize(value_tokens));
            return (false);
        }
        
        g_trades[i] = value_tokens[1];
    }
    
    return (true);
}

bool is_trade_closed(int order)
{
    return (OrderSelect(order, SELECT_BY_TICKET, MODE_HISTORY) && (OrderCloseTime() > 1000000000));
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

string random_id()
{
    string alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    string id = "*************************";
    for (int i = 0; i < 25; i++)
    {
        int char = MathRand() % 63;
        char = StringGetChar(alphabet, char);
        id = StringSetChar(id, i, char);
    }
    return (id);
}

void slave_open_trade_to_db(int index, int status)
{
    string status_text = "NULL";
    string open_time = "NULL";
    string slave_trade_id = "NULL";
    double stop_loss = 0;
    double take_profit = 0;
    double commission = 0;

    Print("Status = ", status);
    
    if (status == ERR_NO_ERROR)
    {
        status_text = "NULL";
        open_time = create_db_timestamp(OrderOpenTime());
        slave_trade_id = OrderTicket();
        stop_loss = OrderStopLoss();
        take_profit = OrderTakeProfit();
        commission = OrderCommission();
    }
    else
    {
        status_text = "'" + status + "'";
        open_time = create_db_timestamp(TimeCurrent());
        slave_trade_id = random_id();
    }

    Print("Status text = ", status_text);
    
    string master_trade_id = g_trades[index];
    string master_id = g_current_master_id;
    string instrument = g_trade_instrument[index];
    int direction = g_trade_direction[index];
    double volume = g_trade_volume[index];
    double open_price = g_trade_open_price[index];
    
    string insert_query = "INSERT INTO slave_trades VALUES ('" + master_id + "', '" + instrument + "', " + direction + ", " + DoubleToStr(volume, 5) + ", " + DoubleToStr(open_price, 5) + ", '" + open_time + "', NULL, NULL, '" + master_trade_id + "', " + DoubleToStr(stop_loss, 5) + ", " + DoubleToStr(take_profit, 5)+ ", '" + g_slave_id_setting + "', '" + slave_trade_id + "', " + DoubleToStr(commission, 5) + ", 0, 0, " + status_text + ");";
    string res = pmql_exec(insert_query);

    if (is_error(res))
    {
        Print(res);
        reconnect();
    }
 }

int open_trade(int index)
{
    if (index >= ArraySize(g_trades))
    {
        Print("ERROR: index out of bounds of g_trades.");
        return (ERR_COMMON_ERROR);
    }

    string symb = g_trade_instrument[index];
    int dir = g_trade_direction[index];
    double vol = MathCeil((g_trade_volume[index] * g_trade_scale) / MarketInfo(symb, MODE_LOTSTEP)) * MarketInfo(symb, MODE_LOTSTEP);
    double price = NormalizeDouble(g_trade_open_price[index], MarketInfo(symb, MODE_DIGITS));
    
    RefreshRates();
    
    int order = OrderSend(symb, dir, vol, price, g_max_slippage, 0, 0);
    if(order < 0)
    {
        int error = GetLastError();
        Print("ERROR: OrderSend failed with error #", error);
        return (error);
    }

    OrderSelect(order, SELECT_BY_TICKET);

    g_trade_volume[index] = vol;
    g_trade_open_price[index] = OrderOpenPrice();

    return (ERR_NO_ERROR);
}

int open_trade_in_reverse(int index)
{
    if (index >= ArraySize(g_trades))
    {
        Print("ERROR: index out of bounds of g_trades.");
        return (ERR_COMMON_ERROR);
    }

    string symb = g_trade_instrument[index];
    int dir = g_trade_direction[index];
    
    if (dir == OP_SELL)
        dir = OP_BUY;
    else
        dir = OP_SELL;

    g_trade_direction[index] = dir;

    double vol = MathCeil((g_trade_volume[index] * g_trade_scale) / MarketInfo(symb, MODE_LOTSTEP)) * MarketInfo(symb, MODE_LOTSTEP);
    double price = -1;
    
    RefreshRates();
    
    if (dir == OP_BUY)
        price = NormalizeDouble(MarketInfo(symb, MODE_ASK), MarketInfo(symb, MODE_DIGITS));
    else
        price = NormalizeDouble(MarketInfo(symb, MODE_BID), MarketInfo(symb, MODE_DIGITS));
    
    int order = OrderSend(symb, dir, vol, price, g_max_slippage, 0, 0);
    if(order < 0)
    {
        int error = GetLastError();
        Print("ERROR: OrderSend failed with error #", error);
        return (error);
    }

    OrderSelect(order, SELECT_BY_TICKET);

    g_trade_volume[index] = vol;
    g_trade_open_price[index] = OrderOpenPrice();

    return (ERR_NO_ERROR);
}

void open_trades()
{
    //Take into account slippage, trade reverse, correctly multiply by scale and round lots, round price to the last significant digit for the symbol on this server
    int count = ArraySize(g_trades);
    int status = 0;

    for (int i = 0; i < count; i++)
    {
        if (g_reverse_trades)
        {
            status = open_trade_in_reverse(i);
            slave_open_trade_to_db(i, status);
        }
        else
        {
            status = open_trade(i);
            slave_open_trade_to_db(i, status);
        }
    }
}

bool close_trade(int index)
{
    Print("Close trade #" + g_trades[index]);
    
    int ticket = StrToInteger(g_trades[index]);
    
    if (is_trade_closed(ticket))
        return (true);

    OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES);
    RefreshRates();
    
    int cmd = OrderType();
    //---- first order is buy or sell
    if (cmd == OP_BUY || cmd == OP_SELL)
    {
        while (true)
        {
            if(cmd == OP_BUY) double price = NormalizeDouble(MarketInfo(OrderSymbol(), MODE_BID), MarketInfo(OrderSymbol(), MODE_DIGITS));
                else price = NormalizeDouble(MarketInfo(OrderSymbol(), MODE_ASK), MarketInfo(OrderSymbol(), MODE_DIGITS));
            int result = OrderClose(OrderTicket(), OrderLots(), price, 3, CLR_NONE);
            
            if(result != TRUE) { int error = GetLastError(); Print("LastError = ", error); }
                else error = 0;
            
            if(error == 135) RefreshRates();
                else break;
        }
    }
    
    if (error != 0)
        return (false);
    else
        return (true);
}

void slave_close_trade_to_db(int index)
{    
    double close_price = OrderClosePrice();
    double profit = OrderProfit();
    double swaps = OrderSwap();
    string close_time = create_db_timestamp(TimeCurrent());
    
    Print("close_time = " + close_time);

    string update_query = "update slave_trades set close_price=" + DoubleToStr(close_price, 5) + ", profit=" + DoubleToStr(profit, 5) + ", swaps=" + DoubleToStr(swaps, 5) + ", close_time='" + close_time + "' where slave_id='" + g_slave_id_setting + "' and slave_trade_id='" + g_trades[index] + "';";
    string res = pmql_exec(update_query);

    if (is_error(res))
    {
        Print(res);
        reconnect();
    }
}

void close_trades()
{
    int count = ArraySize(g_trades);
    int status = 0;

    for (int i = 0; i < count; i++)
    {
        if (close_trade(i))
            slave_close_trade_to_db(i);
    }
}

bool get_trades_to_open()
{
    string query = "select * from master_trades where master_id = '" + g_current_master_id + "' and close_time is null and trade_id not in (select master_trade_id from slave_trades where close_time is null and master_id = '" + g_current_master_id + "' and slave_id = '" + g_slave_id_setting + "');";
    string rows = pmql_exec(query);
    return (open_trades_from_rows(rows));
}

bool closed_trades_from_rows(string rows)
{
    int trades_count = row_count(rows);

    ArrayResize(g_trades, trades_count);
    ArrayResize(g_trade_instrument, trades_count);
    ArrayResize(g_trade_direction, trades_count);
    ArrayResize(g_trade_volume, trades_count);
    ArrayResize(g_trade_open_price, trades_count);

    if (trades_count == 0)
        return (false);

    SplitString(rows, "*", g_trades);

    int tokens_count = ArraySize(g_trades);
    if (tokens_count != trades_count)
    {
        Print("ERROR: tokens_count = ", tokens_count, ", trades_count = ", trades_count);
        return (false);
    }

    for (int i = 0; i < trades_count; i++)
    {
        string trade_tokens[];
        SplitString(g_trades[i], "|", trade_tokens);
        
        if (ArraySize(trade_tokens) < 1)
        {
            Print("ERROR: ArraySize(trade_tokens) = ", ArraySize(trade_tokens));
            return (false);
        }
        
        string value_tokens[];
        SplitString(trade_tokens[0], "=", value_tokens);
        
        if (ArraySize(value_tokens) < 2)
        {
            Print("ERROR: ArraySize(value_tokens) = ", ArraySize(value_tokens));
            return (false);
        }
        
        g_trades[i] = value_tokens[1];        
    }

    return (true);
}

bool get_trades_to_close()
{
    string query = "select st.slave_trade_id from slave_trades st, master_trades mt where st.master_id = '" + g_current_master_id + "' and st.slave_id = '" + g_slave_id_setting + "' and st.close_time is NULL and st.status is NULL and st.master_trade_id = mt.trade_id and mt.close_time is not NULL;";
    string rows = pmql_exec(query);
    return (closed_trades_from_rows(rows));
}

int start()
{
    fill_in_subscribed_masters();
    int masters_count = tokenize_masters();
    Print("Subscribed to " + masters_count + " masters.");

    int cur_master = 0;
    for (; cur_master < masters_count; cur_master++)
        Print("Subscribed master: " + g_master_ids[cur_master]);

    if (tokenize_masters() <= 0)
    {
        Print("ERROR: no subscribed masters!");
        return (-1);
    }

    if (!connect_db())
        return (-1);

    create_db_stucture();
    MathSrand(TimeCurrent());

    datetime prev_time = TimeLocal();

    while (true)
    {
        if ((TimeLocal() - prev_time) >= 1) //Do stuff once per second
        {
            prev_time = TimeLocal();

            cur_master = 0;
            for (; cur_master < masters_count; cur_master++)
            {
                g_current_master_id = g_master_ids[cur_master];

                if (get_trades_to_close())
                    close_trades();

                if (get_trades_to_open())
                    open_trades();
            }
        }

        Sleep(500);
    }

    pmql_disconnect();
    return(0);
}

