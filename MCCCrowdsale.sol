pragma solidity ^0.4.18;

import "./crowdsale/distribution/FinalizableCrowdsale.sol";
import "./lifecycle/Pausable.sol";
import "./fund/ICrowdsaleFund.sol";
import "./common/IEventReturn.sol";
import "./MCCToken.sol";



contract MCCCrowdsale is FinalizableCrowdsale, Pausable, IEventReturn {

    uint256 public constant TOKEN_SALES_MAX = 420000000000000000000000000;

    uint256 public constant PRESALES_OPEN_TIME = 1522508400; //Sun Apr 01 00:00:00 KST 2018
    uint256 public constant PRESALES_CLOSE_TIME = 1523113199; //Sat Apr 07 23:59:59 KST 2018
    uint256 public constant MAINSALES_OPEN_TIME = 1523458800; //Thu Apr 12 00:00:00 KST 2018
    uint256 public constant MAINSALES_CLOSE_TIME = 1525100399; //Mon Apr 30 23:59:59 KST 2018

    uint256 public constant PRIVATESALES_RATE = 14000;
    uint256 public constant PRESALES_RATE = 11500;
    uint256 public constant MAINSALES_RATE = 10000;

    uint256 public constant SOFT_CAP = 5000 ether;
    uint256 public constant HARD_CAP = 40000 ether;

    uint256 public constant PRIVATESALES_MIN_ETHER = 10 ether;
    uint256 public constant PRESALES_MIN_ETHER = 0.5 ether;
    uint256 public constant MAINSALES_MIN_ETHER = 0.2 ether;

    address internal tokenOwner;

    MCCToken public token;
    ICrowdsaleFund public fund;

    int public salesCurrentTrials;       //0 - pre, 1 - main

    struct CrowdSaleInfo {
        uint256 minEtherCap; // 0.5 ether;
        uint256 openTime;
        uint256 closeTime;
        uint256 rate;
        string description; //comments
    }

    CrowdSaleInfo[] inSalesInfoList;

    uint256 refundCompleted;

    uint256 public soldTokensPrivateICO;
    uint256 public soldTokensPreICO;
    uint256 public soldTokensMainICO;

    mapping(address => bool) public whiteList;
    mapping(address => bool) public privateWhiteList;

    address public founderTokenWallet;
    address public researchTokenWallet;
    address public bizDevelopTokenWallet;
    address public markettingTokenWallet;
    address public airdropTokenWallet;

    function MCCCrowdsale(
        address tokenAddress,
        address fundAddress,
        address _founderTokenWallet,
        address _researchTokenWallet,
        address _bizDevelopTokenWallet,
        address _markettingTokenWallet,
        address _airdropTokenWallet,
        address _owner
    ) public
    Crowdsale(PRESALES_RATE, fundAddress, ERC20(tokenAddress))
    TimedCrowdsale(PRESALES_OPEN_TIME, PRESALES_CLOSE_TIME)
    {
        require(tokenAddress != address(0));
        require(fundAddress != address(0));

        token = MCCToken(tokenAddress);
        fund = ICrowdsaleFund(fundAddress);

        founderTokenWallet = _founderTokenWallet;
        researchTokenWallet = _researchTokenWallet;
        bizDevelopTokenWallet = _bizDevelopTokenWallet;
        markettingTokenWallet = _markettingTokenWallet;
        airdropTokenWallet = _airdropTokenWallet;

        tokenOwner = _owner;

        salesCurrentTrials = -1;

        CrowdSaleInfo memory saleInfoPre;

        saleInfoPre.openTime = PRESALES_OPEN_TIME;
        saleInfoPre.closeTime = PRESALES_CLOSE_TIME;
        saleInfoPre.rate = PRESALES_RATE;
        saleInfoPre.minEtherCap = PRESALES_MIN_ETHER;
        saleInfoPre.description = "MCC Token Pre Sales";

        inSalesInfoList.push(saleInfoPre);

        CrowdSaleInfo memory saleInfoMain;

        saleInfoMain.openTime = MAINSALES_OPEN_TIME;
        saleInfoMain.closeTime = MAINSALES_CLOSE_TIME;
        saleInfoMain.rate = MAINSALES_RATE;
        saleInfoMain.minEtherCap = MAINSALES_MIN_ETHER;
        saleInfoMain.description = "MCC Token Main Sales";

        inSalesInfoList.push(saleInfoMain);

        soldTokensPrivateICO = 0;
        soldTokensPreICO = 0;
        soldTokensMainICO = 0;

        paused = true;
    }

   /**
   * @dev Reverts if beneficiary is not whitelisted. Can be used when extending this contract.
   */
    modifier isWhitelisted(address _beneficiary) {
        require(whiteList[_beneficiary]);
        _;
    }

    modifier isPrivateWhitelisted(address _wallet) {
        require(privateWhiteList[_wallet]);
        _;
    }

    /**
     * @dev Set crowdsales information. sale duration, sale tokens rate, softcap etc..
     */
    function setSaleInfo(uint _salesTrials, uint256 _openingTime, uint256 _closingTime, uint256 _rate, uint256 _minETHCap, string _desc) public onlyOwner
    {
        CrowdSaleInfo saleInfo = inSalesInfoList[_salesTrials];

        saleInfo.openTime = _openingTime;
        saleInfo.closeTime = _closingTime;
        saleInfo.rate = _rate;
        saleInfo.minEtherCap = _minETHCap;
        saleInfo.description = _desc;

        if (int(_salesTrials) == salesCurrentTrials) {
            openingTime = saleInfo.openTime;
            closingTime = saleInfo.closeTime;
            rate = saleInfo.rate;
        }
        fncReturnVAL(uint256(0));
    }

    /**
     * @dev Get current sales information.
     */
    function getCurrentSalesInfo() public view returns (uint256, uint256, uint256, uint256, string) {
        require(salesCurrentTrials >= 0);
        
        CrowdSaleInfo memory saleInfo = inSalesInfoList[uint(salesCurrentTrials)];

        return (saleInfo.openTime, saleInfo.closeTime, saleInfo.rate, saleInfo.minEtherCap, saleInfo.description);
    }

    function startSales(uint _salesTrial) public onlyOwner {
        require(int(_salesTrial) >= salesCurrentTrials);
        
        CrowdSaleInfo memory saleInfo = inSalesInfoList[_salesTrial];

        require(0 < saleInfo.rate);
        require(now < saleInfo.closeTime);

        salesCurrentTrials = int(_salesTrial);

        openingTime = saleInfo.openTime;
        closingTime = saleInfo.closeTime;
        rate = saleInfo.rate;

        paused = false;

        fncReturnVAL(uint256(0));
    }

    /**
     * @dev Add wallet to whitelist. For contract owner only.
     */
    function addToWhiteList(address _wallet) public onlyOwner {
        whiteList[_wallet] = true;
    }

    /**
    * @dev Adds list of addresses to whitelist. Not overloaded due to limitations with truffle testing. 
    * @param _beneficiaries Addresses to be added to the whitelist
    */
    function addManyToWhitelist(address[] _beneficiaries) external onlyOwner {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            whiteList[_beneficiaries[i]] = true;
        }
        fncReturnVAL(SUCCEED);
    }

    /**
    * @dev Removes single address from whitelist. 
    * @param _beneficiary Address to be removed to the whitelist
    */
    function removeFromWhitelist(address _beneficiary) external onlyOwner {
        whiteList[_beneficiary] = false;
    }

    /**
     *@dev Check if wallet is registered whitelist. 
     */
    function isRegisteredWhiteList(address _beneficiary) external view returns (bool) {
        return whiteList[_beneficiary];
    }

    /**
     * @dev Add wallet to whitelist. For contract owner only.
     */
    function addToPrivateWhiteList(address _wallet) public onlyOwner {
        privateWhiteList[_wallet] = true;
    }
   
    /**
     *@dev Check if wallet is registered private Whitelist. 
     */
    function isRegisteredPrivateWhiteList(address _wallet) public view onlyOwner returns (bool) {
        return privateWhiteList[_wallet];
    }
   
    /**
     * @dev buy tokens who registered private wallet list
     * @param _beneficiary address Account to buyer wallet address.
     */
    function buyTokensPrivate(address _beneficiary) external payable isPrivateWhitelisted(msg.sender) {
        //require(privateWhiteList[msg.sender]);
        require(_beneficiary != address(0));
        require(msg.value >= PRIVATESALES_MIN_ETHER);

        uint256 weiAmount = msg.value;

        // update state
        weiRaised = weiRaised.add(weiAmount);

        //_preValidatePurchase(_beneficiary, weiAmount);

        uint256 _tokenAmount = weiAmount.mul(PRIVATESALES_RATE);

        require(getTotalTokensSold().add(_tokenAmount) <= TOKEN_SALES_MAX);

        //inPrivilegedBuyerList[_beneficiary] = tokens;
        //privilegedBuyerList.push(_beneficiary);

        token.issue(_beneficiary, _tokenAmount);
        fund.processContribution.value(msg.value)(_beneficiary);
        soldTokensPrivateICO = SafeMath.add(soldTokensPrivateICO, _tokenAmount);

        fncReturnVAL(SUCCEED);
    }
  /**
   * @dev Checks whether the cap has been reached.
   * @return Whether the cap was reached
   */
    function capReached() public view returns (bool) {
        return weiRaised >= SOFT_CAP;
    }

    /**
     * @dev Validation of an incoming purchase. Use require statemens to revert state when conditions are not met. Use super to concatenate validations.
     * @param _beneficiary Address performing the token purchase
     * @param _weiAmount Value in wei involved in the purchase
     */
    function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) internal whenNotPaused isWhitelisted(_beneficiary) {
        require(salesCurrentTrials >= 0);
        
        CrowdSaleInfo memory saleInfo = inSalesInfoList[uint(salesCurrentTrials)];
        require(_weiAmount >= saleInfo.minEtherCap);

        super._preValidatePurchase(_beneficiary, _weiAmount);

        require(weiRaised.add(_weiAmount) <= HARD_CAP);
    }

        /**
    * @dev Override _postValidatePurchase function. Not deliver token to beneficiary yet.
    *               distribution including delivering token to beneficiary will be handled on finalization
    */
    function _processPurchase(address _beneficiary, uint256 _tokenAmount) internal {
        require(getTotalTokensSold().add(_tokenAmount) <= TOKEN_SALES_MAX);

        token.issue(msg.sender, _tokenAmount);
       
        if (salesCurrentTrials == 0)
            soldTokensPreICO = SafeMath.add(soldTokensPreICO, _tokenAmount);
        else
            soldTokensMainICO = SafeMath.add(soldTokensMainICO, _tokenAmount);
    }

    /**
    * @dev Overrides Crowdsale fund forwarding, sending funds to vault.
    */
    function _forwardFunds() internal {
        //noting called. fund already forward _processPurchase
        fund.processContribution.value(msg.value)(msg.sender);
    }

    /**
    * @dev Override _postValidatePurchase function. Add msg.sender to buyerList for refund
    */
    function _postValidatePurchase(address _beneficiary, uint256 _weiAmount) internal {
        //addToBuyerList(_beneficiary, _getTokenAmount(_weiAmount));
    }

    /**
     * @dev return total number of tokens sold
    */
    function getTotalTokensSold() internal view returns (uint256) {
        return soldTokensPrivateICO.add(soldTokensPreICO).add(soldTokensMainICO);
    }

    function getRemainTokensToSell() external view returns (uint256) {
        return TOKEN_SALES_MAX.sub(getTotalTokensSold());
    }

   /**
    * @dev Override finalization function. Add distributing token part
    */
    function finalization() internal {
        //super.finalization();
        if (capReached()) {
            fund.onCrowdsaleEnd();
            token.setAllowTransfers(true);
       
            uint256 totalToken = token.totalSupply();

            token.transfer(founderTokenWallet, totalToken.mul(23).div(100));
            token.transfer(researchTokenWallet, totalToken.mul(1).div(100));
            token.transfer(bizDevelopTokenWallet, totalToken.mul(3).div(100));
            token.transfer(markettingTokenWallet, totalToken.mul(2).div(100));
            token.transfer(airdropTokenWallet, totalToken.mul(29).div(100));

            token.transfer(airdropTokenWallet, token.balanceOf(this));

        } else {
            fund.enableCrowdsaleRefund();
        }
        token.finishIssuance();
    }

}