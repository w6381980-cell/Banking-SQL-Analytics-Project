use Banking;

-- =============================================
-- MSSQL BANKING SYSTEM - SCHEMA & BACKEND LOGIC
-- =============================================

-- 1. ROLES AND USERS
CREATE TABLE Roles (
    RoleID INT PRIMARY KEY,
    RoleName VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE Users (
    UserID INT PRIMARY KEY IDENTITY,
    Username VARCHAR(50) UNIQUE NOT NULL,
    PasswordHash VARCHAR(255) NOT NULL,
    FullName VARCHAR(100),
    Email VARCHAR(100),
    Phone VARCHAR(15),
    RoleID INT FOREIGN KEY REFERENCES Roles(RoleID),
    CreatedAt DATETIME DEFAULT GETDATE()
);

CREATE TABLE UserSessions (
    SessionID INT PRIMARY KEY IDENTITY,
    UserID INT FOREIGN KEY REFERENCES Users(UserID),
    LoginTime DATETIME DEFAULT GETDATE(),
    LogoutTime DATETIME NULL
);

-- 2. ACCOUNT TYPES AND CUSTOMER ACCOUNTS
CREATE TABLE AccountTypes (
    AccountTypeID INT PRIMARY KEY,
    TypeName VARCHAR(50),
    MinimumBalance DECIMAL(18,2) NOT NULL
);

CREATE TABLE CustomerAccounts (
    AccountID BIGINT PRIMARY KEY,
    UserID INT FOREIGN KEY REFERENCES Users(UserID),
    AccountTypeID INT FOREIGN KEY REFERENCES AccountTypes(AccountTypeID),
    Balance DECIMAL(18,2) DEFAULT 0,
    IsVerified BIT DEFAULT 0,
    CreatedAt DATETIME DEFAULT GETDATE()
);
CREATE PROCEDURE sp_CreateCustomerAccount
    @UserID INT,
    @AccountTypeID INT,
    @InitialDeposit DECIMAL(18,2),
    @NewAccountID BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RandomAccountNumber BIGINT
    SET @RandomAccountNumber = ABS(CHECKSUM(NEWID())) % 10000000000  -- 10-digit number

    -- Ensure uniqueness
    WHILE EXISTS (SELECT 1 FROM CustomerAccounts WHERE AccountID = @RandomAccountNumber)
    BEGIN
        SET @RandomAccountNumber = ABS(CHECKSUM(NEWID())) % 10000000000
    END

    -- Insert account
    INSERT INTO CustomerAccounts (AccountID, UserID, AccountTypeID, Balance, IsVerified)
    VALUES (@RandomAccountNumber, @UserID, @AccountTypeID, @InitialDeposit, 0)

    SET @NewAccountID = @RandomAccountNumber
END

DECLARE @NewID BIGINT
EXEC sp_CreateCustomerAccount @UserID = 1, @AccountTypeID = 1, @InitialDeposit = 5000, @NewAccountID = @NewID OUTPUT
SELECT @NewID



-- 3. TRANSACTIONS (CASH, CHEQUE)
CREATE TABLE Transactions (
    TransactionID BIGINT PRIMARY KEY IDENTITY,
    AccountID BIGINT FOREIGN KEY REFERENCES CustomerAccounts(AccountID),
    Type VARCHAR(20), -- Deposit, Withdrawal, Cheque
    Amount DECIMAL(18,2) NOT NULL,
    TransactionDate DATETIME DEFAULT GETDATE(),
    Description VARCHAR(255)
);

-- Prevent withdrawals below minimum balance
CREATE TRIGGER trg_CheckMinBalance
ON Transactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM Inserted i
        JOIN CustomerAccounts ca ON i.AccountID = ca.AccountID
        JOIN AccountTypes at ON ca.AccountTypeID = at.AccountTypeID
        WHERE i.Type = 'Withdrawal' AND ca.Balance - i.Amount < at.MinimumBalance
    )
    BEGIN
        RAISERROR('Transaction would breach minimum balance requirement.', 16, 1);
        ROLLBACK;
    END
END;

-- 4. LOAN MODULE
CREATE TABLE LoanTypes (
    LoanTypeID INT PRIMARY KEY,
    TypeName VARCHAR(50),
    InterestRate DECIMAL(5,2)
);

CREATE TABLE LoanApplications (
    LoanID BIGINT PRIMARY KEY IDENTITY,
    UserID INT FOREIGN KEY REFERENCES Users(UserID),
    LoanTypeID INT FOREIGN KEY REFERENCES LoanTypes(LoanTypeID),
    PrincipalAmount DECIMAL(18,2),
    TenureMonths INT,
    Status VARCHAR(20) DEFAULT 'Pending',
    AppliedAt DATETIME DEFAULT GETDATE(),
    ApprovedBy INT FOREIGN KEY REFERENCES Users(UserID),
    ApprovedAt DATETIME NULL
);

CREATE TABLE LoanEMIs (
    EMIID BIGINT PRIMARY KEY IDENTITY,
    LoanID BIGINT FOREIGN KEY REFERENCES LoanApplications(LoanID),
    DueDate DATE,
    Amount DECIMAL(18,2),
    IsPaid BIT DEFAULT 0,
    PaidDate DATE NULL
);

-- Procedure to generate EMIs
CREATE PROCEDURE sp_GenerateEMISchedule
    @LoanID BIGINT
AS
BEGIN
    DECLARE @Principal DECIMAL(18,2), @Tenure INT, @InterestRate DECIMAL(5,2), @MonthlyEMI DECIMAL(18,2)

    SELECT @Principal = PrincipalAmount, @Tenure = TenureMonths, @InterestRate = lt.InterestRate
    FROM LoanApplications l
    JOIN LoanTypes lt ON l.LoanTypeID = lt.LoanTypeID
    WHERE LoanID = @LoanID

    SET @MonthlyEMI = ROUND(@Principal * (1 + @InterestRate/100), 2) / @Tenure

    DECLARE @i INT = 1
    WHILE @i <= @Tenure
    BEGIN
        INSERT INTO LoanEMIs (LoanID, DueDate, Amount)
        VALUES (@LoanID, DATEADD(MONTH, @i, GETDATE()), @MonthlyEMI)
        SET @i += 1
    END
END

-- 5. CARDS MODULE
CREATE TABLE CardTypes (
    CardTypeID INT PRIMARY KEY,
    TypeName VARCHAR(20) -- Debit, Credit
);

CREATE TABLE CardApplications (
    CardAppID INT PRIMARY KEY IDENTITY,
    UserID INT FOREIGN KEY REFERENCES Users(UserID),
    CardTypeID INT FOREIGN KEY REFERENCES CardTypes(CardTypeID),
    Status VARCHAR(20) DEFAULT 'Pending',
    AppliedAt DATETIME DEFAULT GETDATE(),
    ApprovedBy INT FOREIGN KEY REFERENCES Users(UserID),
    ApprovedAt DATETIME NULL
);

CREATE TABLE UserCards (
    CardID BIGINT PRIMARY KEY IDENTITY,
    CardAppID INT FOREIGN KEY REFERENCES CardApplications(CardAppID),
    CardNumber CHAR(16) UNIQUE,
    ExpiryDate DATE,
    CVV CHAR(3),
    IssuedAt DATETIME DEFAULT GETDATE()
);

-- 6. BILL PAYMENTS
CREATE TABLE Billers (
    BillerID INT PRIMARY KEY,
    BillerName VARCHAR(100)
);

CREATE TABLE BillPayments (
    BillID INT PRIMARY KEY IDENTITY,
    UserID INT FOREIGN KEY REFERENCES Users(UserID),
    BillerID INT FOREIGN KEY REFERENCES Billers(BillerID),
    Amount DECIMAL(18,2),
    DueDate DATE,
    IsPaid BIT DEFAULT 0,
    PaidAt DATETIME NULL
);
-- Sample Data: Roles and Users
INSERT INTO Roles VALUES (1, 'Customer'), (2, 'Employee'), (3, 'Admin');

INSERT INTO Users (Username, PasswordHash, FullName, Email, Phone, RoleID)
VALUES
('cust1', 'hash1', 'John Doe', 'john@example.com', '1234567890', 1),
('emp1', 'hash2', 'Alice Smith', 'alice@example.com', '0987654321', 2),
('admin1', 'hash3', 'Super Admin', 'admin@example.com', '1122334455', 3);
-- Sample Data: Account Types
INSERT INTO AccountTypes VALUES (1, 'Saving', 1000.00), (2, 'Current', 5000.00);

-- Sample Data: Customer Account
INSERT INTO CustomerAccounts VALUES (1000000001, 1, 1, 5000.00, 1, GETDATE());
-- Sample Data: Transactions

INSERT INTO Transactions (AccountID, Type, Amount, Description)
VALUES
(1000000001, 'Deposit', 2000.00, 'Initial Deposit'),
(1000000001, 'Withdrawal', 1000.00, 'ATM Withdrawal');

-- Sample Data: Loan Types
INSERT INTO LoanTypes VALUES (1, 'Home', 7.5), (2, 'Personal', 12.0), (3, 'Business', 10.0), (4, 'Student', 5.0);

-- Sample Loan Application
INSERT INTO LoanApplications (UserID, LoanTypeID, PrincipalAmount, TenureMonths, ApprovedBy, ApprovedAt)
VALUES (1, 1, 1000000, 12, 3, GETDATE());

-- Sample Data: Card Types and Application
INSERT INTO CardTypes VALUES (1, 'Debit'), (2, 'Credit');
INSERT INTO CardApplications (UserID, CardTypeID, ApprovedBy, ApprovedAt) VALUES (1, 1, 2, GETDATE());

-- Sample Data: Billers and Payments
INSERT INTO Billers VALUES (1, 'Electricity'), (2, 'Water'), (3, 'Internet');
INSERT INTO BillPayments (UserID, BillerID, Amount, DueDate) VALUES (1, 1, 2500.00, DATEADD(DAY, 7, GETDATE()));


-- 7. SCHEDULED JOBS
-- Use SQL Server Agent Job (outside T-SQL) to schedule this
-- Example reminder job:
SELECT * FROM LoanEMIs WHERE DueDate = CAST(GETDATE() + 1 AS DATE) AND IsPaid = 0
 SELECT * FROM BillPayments WHERE DueDate = CAST(GETDATE() + 1 AS DATE) AND IsPaid = 0

SELECT * FROM Roles;
SELECT * FROM Users;
SELECT * FROM UserSessions;

SELECT * FROM AccountTypes;
SELECT * FROM CustomerAccounts;

SELECT * FROM Transactions;


SELECT * FROM LoanTypes;
SELECT * FROM LoanApplications;
SELECT * FROM LoanEMIs;

SELECT * FROM CardTypes;
SELECT * FROM CardApplications;
SELECT * FROM UserCards;

SELECT * FROM Billers;
SELECT * FROM BillPayments;


