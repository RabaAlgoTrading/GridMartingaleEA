#property copyright "Aleix Rabassa"
#property link      "https://linktr.ee/raba.algotrading"

// libs.
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Arrays\ArrayLong.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Arrays\ArrayInt.mqh>

/**
 * EXPERT INPUTS
 */
input ulong InpExpertMagic = 0;                         // Expert magic number [0 - random]
input bool InpEnableGrid = true;                        // Enable grid strategy (For testing. If false, only initial positions will be opened)
input bool InpEnableMartingale = true;                  // Enable martingale strategy (For testing.)
input double InpGridDistancePips = 100;                 // Grid distance (pips)
input double InpMartingaleDistancePips = 20;            // Martingale distanes (pips)
input double InpMartingaleMultiplier = 2;               // Martingale multiplier
input double InpVolume = 0.01;                          // Volume (lots)
input double InpTPBalance = 0.1;                        // TP ($)
input double InpGlobalTPBalance = 5;                    // Global TP ($) [0 - disabled]
input bool InpDrawGrid = false;                         // Draw grid lines    
input int InpMaxSpread = 0;                             // Max. spread allowed [0 - disabled]

/**
 * GLOBAL VARIABLES
 */
CPositionInfo position;
CTrade trade; 
CArrayDouble *grid = new CArrayDouble();
MqlTick tick_array[];
int gridTolerancePoints = (int) InpGridDistancePips * 10 / 3; 
CArrayObj martingaleList = new CArrayObj();
double startingBalance;

void OpenPositions(void)
{
    if (!PositionTypeExists(POSITION_TYPE_BUY)) {
    
        // Open new buy martingale.
        CMartingale *newMartingale = new CMartingale();
        newMartingale.Start(POSITION_TYPE_BUY);
        martingaleList.Add(newMartingale);
    }
    
    if (!PositionTypeExists(POSITION_TYPE_SELL)) {
    
        // Open new sell martingale.
        CMartingale *newMartingale = new CMartingale();
        newMartingale.Start(POSITION_TYPE_SELL);
        martingaleList.Add(newMartingale);
    }
}

void GridInit(void)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double avg = (ask + bid) / 2;
    
    grid.Add(avg - InpGridDistancePips * 10 * _Point);
    grid.Add(avg);
    grid.Add(avg + InpGridDistancePips * 10 * _Point);
}

void UpdateGrid(int pGridIndexTouched)
{    
    double currGridPrice = grid.At(pGridIndexTouched);
    
    grid.Clear();
    grid.Add(currGridPrice - InpGridDistancePips * 10 * _Point);
    grid.Add(currGridPrice);
    grid.Add(currGridPrice + InpGridDistancePips * 10 * _Point);

    // Draw lines if needed.
    if (InpDrawGrid) DrawGrid();
}

int GridLevelIsTouched(void)
{    
    CopyTicks(_Symbol, tick_array, COPY_TICKS_ALL, 0, 2);

    // Loop grid levels.
    for (int i = 0; i < grid.Total(); i++) {
    
        // If price crosses the current grid level.
        if ((tick_array[1].ask <= grid.At(i) && tick_array[0].ask >= grid.At(i))
                    || (tick_array[1].bid >= grid.At(i) && tick_array[0].bid <= grid.At(i))) {
            return i;       
        }
    }    
    return -1;
}

void DrawGrid(void)
{
    ObjectsDeleteAll(0);
    for (int i = 0; i < grid.Total(); i++) {
        ObjectCreate(0, "grid" + string(i), OBJ_HLINE, 0, 0, grid.At(i));
    }
}

// Returns true if a positions of type pType opened at the current price exists. False if not.
bool PositionTypeExists(ENUM_POSITION_TYPE pType)
{    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double avg = (ask + bid) / 2;
    
    for (int i = 0; i < PositionsTotal(); i++) {
        position.SelectByIndex(i);
        
        // Skip iteration if different type.
        if (position.PositionType() != pType) continue;
        
        // Skip if is a martingale position.
        if (MartingaleListExists(position.Ticket())) continue; 
        
        // If price open is on the current price +- gridTolerancePoints return true.
        if (position.PriceOpen() <= avg + gridTolerancePoints * _Point
                    && position.PriceOpen() >= avg - gridTolerancePoints * _Point) {
            return true;
        }
    }
    return false;
}

bool GlobalTPisReached(void)
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double goalBalance = startingBalance + InpGlobalTPBalance;    
    return equity >= goalBalance;
}

void CloseAllPositions(void)
{
    for (int i = 0; i < PositionsTotal(); i++) {
        position.SelectByIndex(i); 
        if (position.Magic() != InpExpertMagic) continue;   
        trade.PositionClose(position.Ticket());
    }
}

/**
 * MartingaleList methods
 */
void MartingaleListTick(void)
{
    // Stop closed martingales.
    MartingaleListMaintenance();
    
    for (int i = 0; i < martingaleList.Total(); i++) {
        CMartingale *mg = martingaleList.At(i);
        mg.Tick();
    }
}

bool MartingaleListExists(ulong pTicket)
{
    for (int i = 0; i < martingaleList.Total(); i++) {
        CMartingale *mg = martingaleList.At(i);
        if (mg.Exists(pTicket)) {
            return true;
        }
    }
    return false;
}

void MartingaleListMaintenance(void)
{
    CArrayInt *toDelete = new CArrayInt();
    
    for (int i = 0; i < martingaleList.Total(); i++) {
        CMartingale *mg = martingaleList.At(i);
        if (!position.SelectByTicket(mg.GetTicketAt(0))) {
            toDelete.Add(i);
        }        
    }
    
    for (int i = toDelete.Total() - 1; i >= 0; i--) {
        martingaleList.Delete(toDelete.At(i));
    }
        
    delete toDelete;
}

/**
 * CMartingale class
 */
class CMartingale : public CObject
{
    public:
        void Tick(void);
        bool Exists(ulong pTicket);
        long GetTicketAt(int pIndex);
        void Start(ENUM_POSITION_TYPE pType);         
        CMartingale(void);
        
    private:
        CArrayLong *ticketList;
        double distance;
        double multiplier;
        int counter;
        ENUM_POSITION_TYPE type;
        bool active;
        double CalcTakeProfit();
        double CalcMartingaleTakeProfit();
        double CalcTPPointsByBalance(double pVolume);
        void UpdateTakeProfits();
};

void CMartingale::CMartingale(void)
{
    ticketList = new CArrayLong();
    distance = InpMartingaleDistancePips * 10;
    multiplier = InpMartingaleMultiplier;
    counter = 0;   
    active = true;   
}

void CMartingale::Tick(void)
{ 
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    if (!active) return;
    
    // Select last position of the martingale.
    ulong lastTicket = ticketList.At(ticketList.Total() - 1);    
    position.SelectByTicket(lastTicket);
    
    if (type == POSITION_TYPE_BUY) {
        if (ask <= position.PriceOpen() - distance * _Point) {    
            trade.Buy(InpVolume * pow(multiplier, counter), _Symbol, ask, 0, CalcTakeProfit());
            position.SelectByIndex(PositionsTotal() - 1);
            ticketList.Add(position.Ticket());
            UpdateTakeProfits();
            counter++;
        }
    }
    
    if (type == POSITION_TYPE_SELL) {
        if (bid >= position.PriceOpen() + distance * _Point) {         
            trade.Sell(InpVolume * pow(multiplier, counter), _Symbol, bid, 0, CalcTakeProfit());
            position.SelectByIndex(PositionsTotal() - 1);
            ulong ticket = position.Ticket();
            ticketList.Add(position.Ticket());
            UpdateTakeProfits();
            counter++;
        }
    }
}

bool CMartingale::Exists(ulong pTicket)
{ 
    for (int i = 1; i < ticketList.Total(); i++) {
        if (ticketList.At(i) == pTicket) return true;
    }
    return false;
}

long CMartingale::GetTicketAt(int pIndex)
{
    return ticketList.At(pIndex);  
}

void CMartingale::Start(ENUM_POSITION_TYPE pType)
{ 
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    type = pType;
    
    if (pType == POSITION_TYPE_BUY) {
        trade.Buy(InpVolume, _Symbol, ask, 0, CalcTakeProfit()); 
    }
    
    if (pType == POSITION_TYPE_SELL) {
        trade.Sell(InpVolume, _Symbol, bid, 0, CalcTakeProfit());
    }
    
    position.SelectByIndex(PositionsTotal() - 1);
    ticketList.Add(position.Ticket());
    counter++;    
}

void CMartingale::UpdateTakeProfits()
{
    double tp = NormalizeDouble(CalcMartingaleTakeProfit(), _Digits);
    for (int i = 0; i < ticketList.Total(); i++) {
        trade.PositionModify(ticketList.At(i), 0, tp);  
    }
}

double CMartingale::CalcTakeProfit()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    if (type == POSITION_TYPE_BUY)          return NormalizeDouble(ask + CalcTPPointsByBalance(), _Digits);
    else if (type == POSITION_TYPE_SELL)    return NormalizeDouble(bid - CalcTPPointsByBalance(), _Digits);
    return -1;
}

double CMartingale::CalcMartingaleTakeProfit(void)
{
    double priceLotsSum = 0;
    double lotsSum = 0;
    
    for (int i = 0; i < ticketList.Total(); i++) {
        position.SelectByTicket(ticketList.At(i));
        priceLotsSum += position.PriceOpen() * position.Volume();
        lotsSum += position.Volume();
    }

    if (lotsSum == 0) {
        lotsSum = lotsSum;
    }
    
    double breakEven = priceLotsSum / lotsSum;
    double takeProfit = breakEven;
    if (type == POSITION_TYPE_BUY)  takeProfit += CalcTPPointsByBalance(lotsSum);
    if (type == POSITION_TYPE_SELL) takeProfit -= CalcTPPointsByBalance(lotsSum);
    return takeProfit;
}

double CMartingale::CalcTPPointsByBalance(double pVolume = 0)
{
   if (pVolume == 0) pVolume = InpVolume;
   
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ticksPerPoint = tickSize / point;
   double pointValue = tickValue / ticksPerPoint;
   double points = InpTPBalance / (pointValue * pVolume) * _Point;
   return points;
}